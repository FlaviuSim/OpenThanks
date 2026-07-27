import SwiftUI
import WatchKit

private let watchCoral = Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)

struct WatchRootView: View {
    @Environment(WatchPhoneSession.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn {
                    WatchComposeView()
                } else {
                    signedOut
                }
            }
        }
        .onChange(of: session.pendingComposeFocus) { _, focus in
            if focus { session.pendingComposeFocus = false }
        }
    }

    private var signedOut: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(watchCoral)
            Text("Sign in on iPhone")
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
            Text("Open OpenThanks on your iPhone, then come back to speak a thanks here.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .navigationTitle("OpenThanks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchComposeView: View {
    @Environment(WatchPhoneSession.self) private var session
    @State private var message = ""
    @State private var recipient = ""
    @State private var status: Status = .idle
    @State private var pendingWaiting = 0

    private enum Status: Equatable {
        case idle
        case sending
        case success
        case queued(String)
        case failed(String)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasMessage: Bool { !trimmedMessage.isEmpty }

    private var canSend: Bool {
        hasMessage && status != .sending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                brandRow

                switch status {
                case .success:
                    successCard
                default:
                    if hasMessage {
                        reviewCard
                        actionsWhenReady
                    } else {
                        emptyDictateCard
                    }
                    statusBanner
                    footnotes
                }
            }
            .padding(.vertical, 2)
        }
        .navigationTitle("Thank someone")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pendingWaiting = WidgetSnapshotStore.load().pendingToAccept
        }
    }

    private var brandRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(watchCoral)
            Text("OpenThanks")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(watchCoral)
            Spacer(minLength: 0)
        }
    }

    /// Voice-first empty state — one big speak control, no tiny keyboard.
    private var emptyDictateCard: some View {
        VStack(spacing: 14) {
            Text("Say it while it matters.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Button(action: dictateMessage) {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Speak thanks")
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(watchCoral, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speak your appreciation")

            Button(action: dictateRecipient) {
                Text(recipient.isEmpty ? "Add a name (optional)" : "To: \(recipient)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your note")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("“\(trimmedMessage)”")
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if !recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("To \(recipient.trimmingCharacters(in: .whitespacesAndNewlines))")
                    .font(.caption2)
                    .foregroundStyle(watchCoral)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }

    private var actionsWhenReady: some View {
        VStack(spacing: 8) {
            Button {
                Task { await send() }
            } label: {
                Group {
                    if status == .sending {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Label("Send", systemImage: "heart.fill")
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canSend ? watchCoral : Color.gray.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            HStack(spacing: 10) {
                Button("Speak again", action: dictateMessage)
                Button(recipient.isEmpty ? "Add To" : "Edit To", action: dictateRecipient)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(status == .sending)
        }
    }

    private var successCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(watchCoral)
            Text("Sent — thank you")
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
            Text("That note is on its way.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Speak another") {
                status = .idle
                message = ""
                recipient = ""
            }
            .font(.caption)
            .foregroundStyle(watchCoral)
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch status {
        case .idle, .sending, .success:
            EmptyView()
        case .queued(let note):
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let note):
            VStack(alignment: .leading, spacing: 6) {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") {
                    Task { await send() }
                }
                .font(.caption2)
                .foregroundStyle(watchCoral)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var footnotes: some View {
        if session.queuedCount > 0 || pendingWaiting > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if session.queuedCount > 0 {
                    Text(
                        session.queuedCount == 1
                            ? "1 note waiting for iPhone"
                            : "\(session.queuedCount) notes waiting for iPhone"
                    )
                }
                if pendingWaiting > 0 {
                    Text(
                        pendingWaiting == 1
                            ? "1 appreciation waiting on iPhone"
                            : "\(pendingWaiting) appreciations waiting on iPhone"
                    )
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Voice input

    private func dictateMessage() {
        presentVoiceInput(
            suggestions: [
                "Thank you for everything.",
                "I'm grateful for you.",
                "You made a difference.",
            ]
        ) { spoken in
            let clipped = String(spoken.prefix(WatchRelay.watchMessageMaxLength))
            message = clipped
            if case .failed = status { status = .idle }
            if case .queued = status { status = .idle }
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func dictateRecipient() {
        presentVoiceInput(suggestions: nil) { spoken in
            recipient = spoken
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func presentVoiceInput(
        suggestions: [String]?,
        onResult: @escaping (String) -> Void
    ) {
        guard let controller = WKApplication.shared().visibleInterfaceController else { return }
        // `.plain` opens the Watch text input sheet where dictation is the natural path
        // (mic / scribble / emoji) — not an always-on tiny keyboard field.
        controller.presentTextInputController(
            withSuggestions: suggestions,
            allowedInputMode: .plain
        ) { result in
            guard let items = result as? [String],
                  let text = items.first?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { return }
            Task { @MainActor in
                onResult(text)
            }
        }
    }

    private func send() async {
        status = .sending
        let outcome = await session.sendAppreciation(message: message, recipient: recipient)
        switch outcome {
        case .sent:
            status = .success
            message = ""
            recipient = ""
            WKInterfaceDevice.current().play(.success)
        case .queued(let note):
            status = .queued(note)
            message = ""
            recipient = ""
        case .failed(let note):
            status = .failed(note)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
