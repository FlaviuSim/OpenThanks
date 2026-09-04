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

    @State private var status: Status = .idle
    @State private var pendingWaiting = 0
    @State private var isPresentingRecorder = false
    @State private var inputGeneration = 0

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
            if phase == .active {
                Task { await session.flushQueueIfPossible() }
                Task { await autoStartRecordingIfNeeded() }
            }
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

            Button {
                Task { await startRecording() }
            } label: {
                recordButtonLabel(title: "Record a thanks", systemImage: "waveform")
            }
            .buttonStyle(.plain)
            .disabled(isPresentingRecorder)
            .accessibilityLabel("Record a thanks")
        }
    }

    private func recordButtonLabel(title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
            Text(title)
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
            Text("Sending to iPhone to turn into text. Keep the phone nearby.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
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
            Text("On iPhone in Pending — send it to the recipient when ready.")
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

            Button("Try again") {
                Task { await startRecording() }
            }
            .font(.caption)
            .foregroundStyle(watchCoral)
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

    // MARK: - Recording

    private func autoStartRecordingIfNeeded() async {
        guard session.pendingAutoRecord else { return }
        session.pendingAutoRecord = false
        try? await Task.sleep(for: .milliseconds(350))
        guard scenePhase == .active, !isPresentingRecorder else { return }
        if case .saving = status { return }
        await startRecording()
    }

    /// System Watch audio recorder (mic UI) — not the text/keyboard sheet.
    private func startRecording() async {
        guard !isPresentingRecorder else { return }
        guard status != .saving else { return }
        status = .idle

        // Retry briefly — SwiftUI can report a nil host right after appear.
        var controller: WKInterfaceController?
        for attempt in 0..<6 {
            controller = visibleInterfaceController()
            if controller != nil { break }
            if attempt < 5 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
        guard let controller else {
            status = .failed("Couldn't open the recorder — open the app again and try.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openthanks-watch-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: url)

        isPresentingRecorder = true
        inputGeneration += 1
        let generation = inputGeneration

        let options: [String: Any] = [
            WKAudioRecorderControllerOptionsActionTitleKey: "Save thanks",
            WKAudioRecorderControllerOptionsAutorecordKey: true,
            WKAudioRecorderControllerOptionsMaximumDurationKey: 90.0,
        ]

        controller.presentAudioRecorderController(
            withOutputURL: url,
            preset: .wideBandSpeech,
            options: options
        ) { didSave, error in
            Task { @MainActor in
                guard generation == self.inputGeneration else { return }

                if let error {
                    self.isPresentingRecorder = false
                    self.status = .failed(error.localizedDescription)
                    WKInterfaceDevice.current().play(.failure)
                    try? FileManager.default.removeItem(at: url)
                    return
                }
                guard didSave else {
                    // User cancelled.
                    self.isPresentingRecorder = false
                    self.status = .idle
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                // Set Saving before dismissing the system recorder so the
                // Record button doesn't flash underneath.
                self.status = .saving
                self.isPresentingRecorder = false
                WKInterfaceDevice.current().play(.click)
                let outcome = await self.session.sendVoiceAppreciation(fileURL: url)
                // Session keeps a durable copy until transfer finishes.
                try? FileManager.default.removeItem(at: url)

                switch outcome {
                case .sent:
                    self.status = .saved
                    self.pendingWaiting = WidgetSnapshotStore.load().pendingToAccept
                    WKInterfaceDevice.current().play(.success)
                case .queued(let note):
                    self.status = .queued(note)
                case .failed(let note):
                    self.status = .failed(note)
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }

    private func visibleInterfaceController() -> WKInterfaceController? {
        if let controller = WKApplication.shared().visibleInterfaceController {
            return controller
        }
        return WKExtension.shared().visibleInterfaceController
    }
}
