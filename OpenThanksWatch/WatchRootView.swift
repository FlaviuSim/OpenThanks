import SwiftUI
import WatchKit

private let watchCoral = Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)

struct WatchRootView: View {
    @Environment(WatchPhoneSession.self) private var session

    var body: some View {
        NavigationStack {
            Group {
                if session.isSignedIn {
                    WatchRecordView()
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

// MARK: - One-button record screen

struct WatchRecordView: View {
    @Environment(WatchPhoneSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    /// Prevents overlapping `presentTextInputController` calls.
    @State private var isPresentingInput = false
    @State private var inputGeneration = 0
    @State private var status: Status = .idle
    @State private var pendingWaiting = 0
    /// Shown only if WatchKit can't present the dictation sheet.
    @State private var showTypeFallback = false

    private enum Status: Equatable {
        case idle
        case saving
        case saved
        case queued(String)
        case failed(String)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch status {
                case .idle:
                    idleContent
                case .saving:
                    savingContent
                case .saved:
                    savedContent
                case .queued(let note):
                    queuedContent(note)
                case .failed(let note):
                    failedContent(note)
                }

                footnotes
            }
            .padding(.vertical, 4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(watchCoral)
                    Text("OpenThanks")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(watchCoral)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("OpenThanks")
            }
        }
        .onAppear {
            pendingWaiting = WidgetSnapshotStore.load().pendingToAccept
            Task { await session.flushQueueIfPossible() }
            Task { await autoStartRecordingIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: session.pendingAutoRecord) { _, should in
            if should {
                Task { await autoStartRecordingIfNeeded() }
            }
        }
    }

    // MARK: - Sub-views

    private var idleContent: some View {
        VStack(spacing: 14) {
            Text("Say it while it matters.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // Prefer WatchKit dictation sheet (mic-first). TextFieldLink opens the
            // QWERTY / scribble keyboard and is only a last-resort fallback.
            Button(action: startRecording) {
                recordButtonLabel
            }
            .buttonStyle(.plain)
            .disabled(isPresentingInput)
            .accessibilityLabel("Record a thanks")

            if showTypeFallback {
                TextFieldLink(prompt: Text("Say your thanks")) {
                    Text("Or type instead")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } onSubmit: { spoken in
                    handleSpokenInput(spoken)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recordButtonLabel: some View {
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

    private var savingContent: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(watchCoral)
                .scaleEffect(1.4)
            Text("Saving…")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var savedContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(watchCoral)
            Text("Saved")
                .font(.system(.headline, design: .rounded))
            Text("On iPhone in Pending — add who to thank when ready.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Record another") {
                status = .idle
            }
            .font(.caption)
            .foregroundStyle(watchCoral)
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func queuedContent(_ note: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(watchCoral)
            Text("Queued")
                .font(.system(.headline, design: .rounded))
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Record another") {
                status = .idle
            }
            .font(.caption)
            .foregroundStyle(watchCoral)
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func failedContent(_ note: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.red)
            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again", action: startRecording)
                .font(.caption)
                .foregroundStyle(watchCoral)
                .buttonStyle(.plain)

            if showTypeFallback {
                TextFieldLink(prompt: Text("Say your thanks")) {
                    Text("Or type instead")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } onSubmit: { spoken in
                    handleSpokenInput(spoken)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
            isPresentingInput = false
            if case .saving = status { status = .failed("Interrupted — please try again.") }
            Task { await session.flushQueueIfPossible() }
            Task { await autoStartRecordingIfNeeded() }
        case .inactive, .background:
            dismissVoiceInputIfNeeded()
        @unknown default:
            break
        }
    }

    private func dismissVoiceInputIfNeeded() {
        guard isPresentingInput else { return }
        textInputController()?.dismissTextInputController()
        isPresentingInput = false
    }

    // MARK: - Recording

    /// Notification / widget / deep link — jump straight into dictation when possible.
    private func autoStartRecordingIfNeeded() async {
        guard session.pendingAutoRecord else { return }
        session.pendingAutoRecord = false
        try? await Task.sleep(for: .milliseconds(350))
        guard scenePhase == .active, !isPresentingInput else { return }
        if case .saving = status { return }
        startRecording()
    }

    /// Mic-first dictation sheet (product intent). Keyboard is only a fallback.
    private func startRecording() {
        status = .idle
        Task { @MainActor in
            await presentSystemDictationWithRetry()
        }
    }

    private func handleSpokenInput(_ spoken: String) {
        let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        showTypeFallback = false
        Task { await saveMessage(text) }
    }

    /// Retries finding the WatchKit host — SwiftUI can briefly report nil right after appear.
    private func presentSystemDictationWithRetry() async {
        guard !isPresentingInput else { return }
        guard scenePhase == .active else { return }

        for attempt in 0..<6 {
            if let controller = textInputController() {
                presentSystemDictation(on: controller)
                return
            }
            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        // Last resort only — TextFieldLink is the keyboard / scribble path.
        showTypeFallback = true
        status = .idle
    }

    private func presentSystemDictation(on controller: WKInterfaceController) {
        showTypeFallback = false
        isPresentingInput = true
        inputGeneration += 1
        let generation = inputGeneration

        // `nil` suggestions + `.plain` is what tells WatchKit to open dictation
        // (not the input picker / TextFieldLink keyboard). Empty array `[]` is wrong.
        let suggestions: [String]? = nil
        controller.presentTextInputController(
            withSuggestions: suggestions,
            allowedInputMode: .plain
        ) { result in
            Task { @MainActor in
                guard generation == self.inputGeneration else { return }
                self.isPresentingInput = false
                guard let items = result as? [String],
                      let text = items.first?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty
                else { return }
                await self.saveMessage(text)
            }
        }
    }

    /// Prefer the modern app controller; fall back for older watchOS hosting.
    private func textInputController() -> WKInterfaceController? {
        if let controller = WKApplication.shared().visibleInterfaceController {
            return controller
        }
        return WKExtension.shared().visibleInterfaceController
    }

    // MARK: - Save

    private func saveMessage(_ raw: String) async {
        let clipped = String(raw.prefix(WatchRelay.watchMessageMaxLength))
        status = .saving
        WKInterfaceDevice.current().play(.click)

        let outcome = await session.sendAppreciation(message: clipped, recipient: nil)
        switch outcome {
        case .sent:
            status = .saved
            pendingWaiting = WidgetSnapshotStore.load().pendingToAccept
            WKInterfaceDevice.current().play(.success)
        case .queued(let note):
            status = .queued(note)
        case .failed(let note):
            status = .failed(note)
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
