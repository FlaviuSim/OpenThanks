import SwiftUI
import UIKit
import LinkPresentation

// MARK: - Share content

/// Copy + assets for sharing an accepted appreciation outside OpenThanks.
struct AppreciationShareContent {
    let url: URL
    let authorName: String
    let recipientName: String
    let message: String
    let mediaURL: URL?
    let mediaType: String?

    init(gratitude: Gratitude) {
        url = gratitude.webURL
        authorName = gratitude.author?.displayName ?? "Someone"
        recipientName = gratitude.recipientDisplayName
        message = gratitude.message.trimmingCharacters(in: .whitespacesAndNewlines)
        mediaURL = gratitude.mediaURL
        mediaType = gratitude.mediaType
    }

    /// Image attachment suitable for the story card (skips video).
    var sharePhotoURL: URL? {
        guard let mediaURL else { return nil }
        if mediaType?.lowercased().hasPrefix("video") == true { return nil }
        return mediaURL
    }

    /// Short quote for cards / captions (keeps Stories & posts readable).
    func quoteSnippet(maxLength: Int = 140) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max(0, maxLength - 3))
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var quoteSnippet: String { quoteSnippet(maxLength: 140) }

    /// Prefill text: message blurb + link (no “X thanked Y” lead-in).
    var caption: String {
        """
        “\(quoteSnippet)”

        \(url.absoluteString)
        """
    }

    /// Caption without the URL — use when the share intent has a separate `url` param (X).
    var captionBody: String {
        "“\(quoteSnippet)”"
    }

    var headline: String {
        "\(authorName) thanked \(recipientName)"
    }

    /// Host + path for display on the card (no scheme).
    var displayLink: String {
        let host = url.host ?? "openthanks.com"
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return host }
        return "\(host)/\(path)"
    }
}

// MARK: - Story card (1080×1920)

struct AppreciationShareCardView: View {
    let content: AppreciationShareContent
    var photo: UIImage? = nil

    private var hasPhoto: Bool { photo != nil }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                if hasPhoto {
                    photoHero
                        .padding(.bottom, 36)

                    quoteBlock(compact: true)

                    Spacer(minLength: 20)

                    smallLinkBar
                } else {
                    Spacer(minLength: 40)

                    quoteBlock(compact: false)

                    Spacer(minLength: 28)

                    smallLinkBar
                }
            }
            .padding(.horizontal, 48)
            .padding(.top, hasPhoto ? 56 : 80)
            .padding(.bottom, 56)
        }
        .frame(width: 1080, height: 1920)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.09, blue: 0.09),
                    Color(red: 0.28, green: 0.14, blue: 0.12),
                    Color(red: 0.86, green: 0.46, blue: 0.36),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 1080, height: 1920)
                    .blur(radius: 48)
                    .opacity(0.35)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.5),
                                Color.black.opacity(0.2),
                                Color(red: 0.86, green: 0.46, blue: 0.36).opacity(0.5),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                Circle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 900, height: 900)
                    .blur(radius: 50)
                    .offset(y: -520)
            }
        }
    }

    private var photoHero: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 984, height: 1_140)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [
                                .black.opacity(0.06),
                                .clear,
                                .black.opacity(0.3),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.5), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 32, y: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func quoteBlock(compact: Bool) -> some View {
        let quote = content.quoteSnippet(maxLength: compact ? 110 : 160)
        return VStack(alignment: .leading, spacing: compact ? 16 : 22) {
            Text("“\(quote)”")
                .font(.system(size: compact ? 32 : 38, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
                .lineSpacing(compact ? 6 : 8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("Tap to read the full appreciation")
                    .font(.system(size: compact ? 22 : 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: compact ? 18 : 20, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE07A5F))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 28 : 36)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.white.opacity(0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
        )
    }

    /// Visual link bar baked into the card (matched by the tappable Stories sticker).
    private var smallLinkBar: some View {
        AppreciationShareLinkBar(displayLink: content.displayLink, compact: true)
    }
}

/// Small link pill used on the card and as the Instagram Stories sticker image.
struct AppreciationShareLinkBar: View {
    let displayLink: String
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: compact ? 22 : 26, weight: .bold))
                .foregroundStyle(Color(hex: 0xE07A5F))
                .frame(width: compact ? 44 : 52, height: compact ? 44 : 52)
                .background(.white, in: Circle())

            Text(displayLink)
                .font(.system(size: compact ? 24 : 26, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.11))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0xE07A5F))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .frame(maxWidth: .infinity)
    }
}

/// Tappable Instagram Stories sticker — same look as the card’s bottom link bar.
/// Instagram opens `linkURL` / `contentURL` when this sticker is tapped.
struct AppreciationShareLinkStickerView: View {
    let content: AppreciationShareContent

    var body: some View {
        AppreciationShareLinkBar(displayLink: content.displayLink, compact: true)
            .frame(width: 920)
    }
}

enum AppreciationShareRenderer {
    @MainActor
    static func storyImage(for content: AppreciationShareContent, photo: UIImage? = nil) -> UIImage? {
        let view = AppreciationShareCardView(content: content, photo: photo)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        if let image = renderer.uiImage { return image }
        // First pass can be nil before layout settles.
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        return renderer.uiImage
    }

    /// Loads an attached photo (if any) then renders the story card.
    @MainActor
    static func storyImage(for content: AppreciationShareContent) async -> UIImage? {
        var photo: UIImage?
        if let url = content.sharePhotoURL {
            photo = await RemoteImageCache.load(url, maxPixelSize: 1_400)
        }
        if let image = storyImage(for: content, photo: photo) { return image }
        await Task.yield()
        return storyImage(for: content, photo: photo)
    }

    @MainActor
    static func linkSticker(for content: AppreciationShareContent) -> UIImage? {
        let view = AppreciationShareLinkStickerView(content: content)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 920, height: 88)
        if let image = renderer.uiImage { return image }
        renderer.proposedSize = ProposedViewSize(width: 920, height: 88)
        return renderer.uiImage
    }
}

// MARK: - System share sheet

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType] = []

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Rich link metadata so Messages / Mail show a nicer preview when possible.
final class AppreciationLinkMetadata: NSObject, UIActivityItemSource {
    let content: AppreciationShareContent
    let image: UIImage?

    init(content: AppreciationShareContent, image: UIImage?) {
        self.content = content
        self.image = image
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        content.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        content.url
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = content.url
        metadata.url = content.url
        metadata.title = content.quoteSnippet
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
        }
        return metadata
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        content.quoteSnippet
    }
}

// MARK: - Channel helpers

enum SocialShare {
    enum Destination: String {
        case instagramStories = "instagram_stories"
        case linkedIn = "linkedin"
        case x = "x"
    }

    enum Outcome {
        /// Opened a native destination or web share intent.
        case opened(hint: String)
    }

    @MainActor
    static func share(
        _ destination: Destination,
        content: AppreciationShareContent,
        cardImage: UIImage?,
        linkSticker: UIImage?,
        openURL: OpenURLAction
    ) async -> Outcome {
        switch destination {
        case .instagramStories:
            return await shareInstagramStories(
                content: content,
                cardImage: cardImage,
                linkSticker: linkSticker,
                openURL: openURL
            )
        case .linkedIn:
            return shareLinkedIn(content: content)
        case .x:
            return shareX(content: content, openURL: openURL)
        }
    }

    /// LinkedIn `share-offsite` only takes a URL; the preview card comes from Open Graph.
    /// Caption cannot be prefilled — we copy it so the user can paste into the post.
    ///
    /// Opens via `UIApplication.open` so LinkedIn’s universal links can hand off to the
    /// app. `OpenURLAction` / in-app Safari / WKWebView will not trigger that handoff.
    @MainActor
    private static func shareLinkedIn(content: AppreciationShareContent) -> Outcome {
        UIPasteboard.general.string = content.captionBody
        var components = URLComponents(string: "https://www.linkedin.com/sharing/share-offsite/")!
        components.queryItems = [URLQueryItem(name: "url", value: content.url.absoluteString)]
        guard let url = components.url else {
            return .opened(hint: "Caption copied — paste into LinkedIn with your link.")
        }
        UIApplication.shared.open(url)
        return .opened(
            hint: "LinkedIn has the link (preview from the page). Caption copied — paste it into your post."
        )
    }

    /// X/Twitter intent prefills text + URL and opens the app or site composer.
    @MainActor
    private static func shareX(
        content: AppreciationShareContent,
        openURL: OpenURLAction
    ) -> Outcome {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")!
        components.queryItems = [
            URLQueryItem(name: "text", value: content.captionBody),
            URLQueryItem(name: "url", value: content.url.absoluteString),
        ]
        if let url = components.url {
            openURL(url)
            return .opened(hint: "X opened with your text and link ready to post.")
        }
        UIPasteboard.general.string = content.caption
        return .opened(hint: "Caption & link copied — paste into X.")
    }

    @MainActor
    private static func shareInstagramStories(
        content: AppreciationShareContent,
        cardImage: UIImage?,
        linkSticker: UIImage?,
        openURL: OpenURLAction
    ) async -> Outcome {
        let source = Bundle.main.bundleIdentifier ?? "com.openthanks.app"
        let storiesURL = URL(string: "instagram-stories://share?source_application=\(source)")!

        if let cardImage,
           let backgroundPNG = cardImage.pngData(),
           UIApplication.shared.canOpenURL(storiesURL) {
            // Do not set pasteboard.string after this — it would wipe the Stories payload.
            var payload: [String: Any] = [
                "com.instagram.sharedSticker.backgroundImage": backgroundPNG,
                "com.instagram.sharedSticker.contentURL": content.url.absoluteString,
                "com.instagram.sharedSticker.linkURL": content.url.absoluteString,
                "com.instagram.sharedSticker.linkText": "OpenThanks",
                "com.instagram.sharedSticker.backgroundTopColor": "#1F1614",
                "com.instagram.sharedSticker.backgroundBottomColor": "#E07A5F",
            ]
            if let stickerPNG = linkSticker?.pngData() {
                payload["com.instagram.sharedSticker.stickerImage"] = stickerPNG
            }

            UIPasteboard.general.setItems(
                [payload],
                options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
            )
            openURL(storiesURL)
            return .opened(
                hint: "Drag the link bar over the bottom of your story, then tap it so people can open this appreciation."
            )
        }

        UIPasteboard.general.string = content.caption
        if let app = URL(string: "instagram://app"),
           UIApplication.shared.canOpenURL(app) {
            openURL(app)
            return .opened(hint: "Caption & link copied — paste into your Instagram post or story.")
        }
        openURL(URL(string: "https://www.instagram.com")!)
        return .opened(hint: "Caption & link copied — paste into Instagram.")
    }

    /// Image for Messages / Mail / etc.: post photo when present, otherwise the story card.
    @MainActor
    static func systemShareItems(
        content: AppreciationShareContent,
        postPhoto: UIImage?,
        cardImage: UIImage?
    ) -> [Any] {
        let image = postPhoto ?? cardImage
        var items: [Any] = [
            content.caption,
            AppreciationLinkMetadata(content: content, image: image),
        ]
        if let image {
            items.insert(image, at: 0)
        }
        return items
    }
}
