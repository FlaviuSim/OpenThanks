import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Share sheet entry point — parse shared content, then hand off to the main app.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareComposeRoot>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)

        let root = ShareComposeRoot(
            extensionItems: extensionContext?.inputItems as? [NSExtensionItem] ?? [],
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            },
            onOpen: { [weak self] payload in
                self?.openInApp(payload)
            }
        )
        let host = UIHostingController(rootView: root)
        hostingController = host
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func openInApp(_ payload: ComposeSharePayload) {
        ComposeShareStore.save(payload)
        // App Group defaults can lag across processes without an explicit flush.
        AppGroup.defaults.synchronize()

        openHostApp(url: WidgetDeepLink.compose) { [weak self] _ in
            // Always finish the share sheet — draft is already in the App Group.
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    /// Share extensions cannot reliably use `extensionContext.open` (Apple only
    /// supports that for Today / iMessage). Walk the responder chain to reach
    /// `UIApplication.open`, which does open our URL scheme.
    private func openHostApp(url: URL, completion: @escaping (Bool) -> Void) {
        // Prefer the supported API first (no-op on share extensions, but cheap).
        if let context = extensionContext {
            context.open(url) { [weak self] success in
                if success {
                    completion(true)
                    return
                }
                let opened = self?.openURLViaResponderChain(url) ?? false
                // Brief delay so SpringBoard can activate the host before we dismiss.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    completion(opened)
                }
            }
            return
        }

        let opened = openURLViaResponderChain(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            completion(opened)
        }
    }

    @discardableResult
    private func openURLViaResponderChain(_ url: URL) -> Bool {
        // Prefer finding UIApplication on the responder chain.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = current.next
        }

        // Fallback: trampoline through `openURL:` (Share Extension pattern).
        return openURLSelectorTrampoline(url)
    }

    /// Declaring `openURL(_:)` lets the system route through UIApplication when
    /// we `perform` up the responder chain.
    @objc @discardableResult
    func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func openURLSelectorTrampoline(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return openURL(url)
    }
}

// MARK: - SwiftUI

struct ShareComposeRoot: View {
    let extensionItems: [NSExtensionItem]
    var onCancel: () -> Void
    var onOpen: (ComposeSharePayload) -> Void

    @State private var draft: ShareInboxParser.Draft?
    @State private var loading = true
    @State private var opening = false

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 16)

            if loading {
                Spacer()
                ProgressView()
                    .tint(SharePalette.coral)
                Spacer()
            } else if let draft {
                content(draft)
            } else {
                Text("Nothing to thank from this share.")
                    .font(.system(size: 15))
                    .foregroundStyle(SharePalette.textSecondary)
                    .padding()
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharePalette.background.ignoresSafeArea())
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ draft: ShareInboxParser.Draft) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(SharePalette.coral)
                Text("OpenThanks")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(SharePalette.coral)
                Spacer()
                Button("Cancel", action: onCancel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SharePalette.textSecondary)
            }

            Text(draft.promptTitle)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(SharePalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                if let name = draft.recipientName {
                    labeled("To", value: name)
                }
                if let message = draft.message {
                    labeled("Note", value: message)
                } else if draft.kind == .photo {
                    labeled("Note", value: "We’ll open a blank appreciation with this photo attached.")
                } else if draft.sourceURL != nil {
                    labeled("From", value: draft.sourceURL ?? "")
                } else {
                    Text("We’ll open compose so you can write the thank-you.")
                        .font(.system(size: 14))
                        .foregroundStyle(SharePalette.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )

            Spacer(minLength: 8)

            Button {
                guard !opening else { return }
                opening = true
                onOpen(makePayload(from: draft))
            } label: {
                HStack {
                    if opening {
                        ProgressView().tint(.white)
                    }
                    Text(opening ? "Opening OpenThanks…" : ctaTitle(for: draft))
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.71, blue: 0.60),
                            Color(red: 0.93, green: 0.48, blue: 0.36),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .disabled(opening)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 22)
    }

    private func labeled(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SharePalette.textSecondary)
            Text(value)
                .font(.system(size: 15))
                .foregroundStyle(SharePalette.textPrimary)
                .lineLimit(4)
        }
    }

    private func ctaTitle(for draft: ShareInboxParser.Draft) -> String {
        switch draft.kind {
        case .contact, .url:
            return draft.recipientName == nil ? "Thank in OpenThanks" : "Thank this person"
        case .photo:
            return "Thanks someone"
        case .calendar:
            return "Thank from this meeting"
        default:
            return "Thank in OpenThanks"
        }
    }

    private func makePayload(from draft: ShareInboxParser.Draft) -> ComposeSharePayload {
        var imageName: String?
        if let data = draft.imageData {
            let uploadData: Data
            if let image = UIImage(data: data),
               let jpeg = image.jpegData(compressionQuality: 0.82) {
                uploadData = jpeg
                imageName = ComposeShareStore.writeImage(uploadData, preferredExtension: "jpg")
            } else {
                imageName = ComposeShareStore.writeImage(data, preferredExtension: draft.imageExtension)
            }
        }
        return .make(
            kind: draft.kind,
            promptTitle: draft.promptTitle,
            recipientName: draft.recipientName,
            message: draft.message,
            sourceURL: draft.sourceURL,
            imageFileName: imageName
        )
    }

    private func load() async {
        let parsed = await ShareInboxParser.parse(extensionItems: extensionItems)
        await MainActor.run {
            draft = parsed
            loading = false
        }
    }
}

private enum SharePalette {
    static let coral = Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)
    static let background = Color(red: 247 / 255, green: 245 / 255, blue: 242 / 255)
    static let textPrimary = Color(red: 26 / 255, green: 26 / 255, blue: 27 / 255)
    static let textSecondary = Color(red: 92 / 255, green: 92 / 255, blue: 98 / 255)
}
