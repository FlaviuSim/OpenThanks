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
    @Environment(\.scenePhase) private var scenePhase

    @State private var message = ""
    @State private var recipient = ""
    @State private var status: Status = .idle
    @State private var pendingWaiting = 0
    /// Prevents overlapping `presentTextInputController` calls (a common Watch crash after interruption).
    @State private var isPresentingInput = false
    /// Bumped when input is cancelled by the system so stale dictation callbacks are ignored.
    @State private var inputGeneration = 0

    private enum Status: Equatable {
        case idle
        case sending
        case success(emailed: Bool)
        case queued(String)
        case failed(String)
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRecipient: String {
        recipient.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasMessage: Bool { !trimmedMessage.isEmpty }

    /// Email in "To" → send a claim link; otherwise save to Pending Appreciations on iPhone.
    private var willEmailFromWatch: Bool {
        WatchRelay.looksLikeEmail(trimmedRecipient)
    }

    private var canSend: Bool {
        hasMessage && !trimmedRecipient.isEmpty && status != .sending && !isPresentingInput
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                brandRow

                switch status {
                case .success(_):
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
        .navigationTitle("Thank Someone")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            restoreComposeDraftIfNeeded()
            pendingWaiting = WidgetSnapshotStore.load().pendingToAccept
            Task { await session.flushQueueIfPossible() }
        }
        .onChange(of: message) { _, _ in persistComposeDraft() }
        .onChange(of: recipient) { _, _ in persistComposeDraft() }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
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
                    Text("Record a thanks")
                        .font(.system(.headline, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(watchCoral, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPresentingInput)
            .accessibilityLabel("Record a thanks")

            Button(action: dictateRecipient) {
                Text(recipient.isEmpty ? "Add name of who to thank" : "To: \(recipient)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isPresentingInput)
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

            if !trimmedRecipient.isEmpty {
                Text("To \(trimmedRecipient)")
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
                        Label(
                            willEmailFromWatch ? "Send" : "Save",
                            systemImage: "heart.fill"
                        )
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

            Text(
                willEmailFromWatch
                    ? "Emails them a link to accept."
                    : "Saves to Pending Appreciations on iPhone — review and share later."
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Record again", action: dictateMessage)
                Button(recipient.isEmpty ? "Add To" : "Edit To", action: dictateRecipient)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(status == .sending || isPresentingInput)
        }
    }

    private var successCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(watchCoral)
            if case .success(let emailed) = status, emailed {
                Text("Sent — thank you")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("We'll email them a link to accept.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Saved — thank you")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("It's in Pending Appreciations on your iPhone — review and share when you're ready.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Record another") {
                status = .idle
                message = ""
                recipient = ""
                WatchComposeDraftStore.clear()
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
        case .idle, .sending, .success(_):
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

    // MARK: - Lifecycle

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Dictation may have been dismissed by the system without a callback.
            isPresentingInput = false
            restoreComposeDraftIfNeeded()
            if case .sending = status {
                // Mid-flight send was interrupted; draft is still local — let them retry.
                status = .idle
            }
            Task { await session.flushQueueIfPossible() }
        case .inactive, .background:
            dismissVoiceInputIfNeeded()
            persistComposeDraft()
        @unknown default:
            persistComposeDraft()
        }
    }

    private func dismissVoiceInputIfNeeded() {
        guard isPresentingInput else { return }
        // Tear down the system sheet cleanly so a later present doesn't crash.
        // Don't bump `inputGeneration` — a completion with spoken text may still arrive.
        WKApplication.shared().visibleInterfaceController?.dismissTextInputController()
        isPresentingInput = false
    }

    private func restoreComposeDraftIfNeeded() {
        guard let draft = WatchComposeDraftStore.load() else { return }
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = draft.message
        }
        if recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipient = draft.recipient
        }
        // Coming back with a saved note should show Save/Send, not a stale success screen.
        if case .success(_) = status, !draft.message.isEmpty {
            status = .idle
        }
    }

    private func persistComposeDraft() {
        switch status {
        case .success(_), .queued:
            WatchComposeDraftStore.clear()
        case .idle, .sending, .failed:
            WatchComposeDraftStore.save(message: message, recipient: recipient)
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
            WatchComposeDraftStore.save(message: clipped, recipient: recipient)
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func dictateRecipient() {
        presentVoiceInput(suggestions: nil) { spoken in
            recipient = spoken
            WatchComposeDraftStore.save(message: message, recipient: spoken)
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func presentVoiceInput(
        suggestions: [String]?,
        onResult: @escaping (String) -> Void
    ) {
        guard !isPresentingInput else { return }
        guard scenePhase == .active else { return }
        guard let controller = WKApplication.shared().visibleInterfaceController else { return }

        isPresentingInput = true
        inputGeneration += 1
        let generation = inputGeneration
        // `.plain` opens the Watch text input sheet where dictation is the natural path
        // (mic / scribble / emoji) — not an always-on tiny keyboard field.
        controller.presentTextInputController(
            withSuggestions: suggestions,
            allowedInputMode: .plain
        ) { result in
            Task { @MainActor in
                guard generation == inputGeneration else { return }
                isPresentingInput = false
                // Cancel / system interruption → nil result. Keep any prior draft intact.
                guard let items = result as? [String],
                      let text = items.first?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return }
                onResult(text)
            }
        }
    }

    private func send() async {
        guard canSend else { return }
        status = .sending
        let outcome = await session.sendAppreciation(message: message, recipient: recipient)
        switch outcome {
        case .sent(let emailed):
            status = .success(emailed: emailed)
            message = ""
            recipient = ""
            WatchComposeDraftStore.clear()
            WKInterfaceDevice.current().play(.success)
        case .queued(let note):
            status = .queued(note)
            message = ""
            recipient = ""
            WatchComposeDraftStore.clear()
        case .failed(let note):
            status = .failed(note)
            // Keep the draft so they can retry after coming back to the Watch.
            WatchComposeDraftStore.save(message: message, recipient: recipient)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
