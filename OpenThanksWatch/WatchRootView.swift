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
                brandRow

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
        .navigationTitle("OpenThanks")
        .navigationBarTitleDisplayMode(.inline)
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

    private var idleContent: some View {
        VStack(spacing: 14) {
            Text("Say it while it matters.")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            // TextFieldLink is the reliable SwiftUI path on watchOS 10+
            // (no dependency on WKInterfaceController being non-nil).
            TextFieldLink(prompt: Text("Say your thanks")) {
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
            } onSubmit: { spoken in
                let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                Task { await saveMessage(text) }
            }
            .buttonStyle(.plain)
            .disabled(isPresentingInput)
            .accessibilityLabel("Record a thanks")
        }
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

            TextFieldLink(prompt: Text("Say your thanks")) {
                Text("Try again")
                    .font(.caption)
                    .foregroundStyle(watchCoral)
            } onSubmit: { spoken in
                let text = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                Task { await saveMessage(text) }
            }
            .buttonStyle(.plain)
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
        presentSystemDictation()
    }

    /// Used for notification auto-start. Manual taps use TextFieldLink (more reliable on older watches).
    private func presentSystemDictation() {
        guard !isPresentingInput else { return }
        guard scenePhase == .active else { return }
        guard let controller = textInputController() else {
            // Can't auto-present — leave idle so the person can tap Record.
            status = .idle
            return
        }

        isPresentingInput = true
        inputGeneration += 1
        let generation = inputGeneration

        controller.presentTextInputController(
            withSuggestions: nil,
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
