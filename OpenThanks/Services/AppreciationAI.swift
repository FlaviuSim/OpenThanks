import AVFoundation
import Foundation
import Speech

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device rewrites via Apple Intelligence (Foundation Models). No network calls.
enum AppreciationAI {
    enum Style: String, CaseIterable, Identifiable {
        case polish
        case shorten
        case warmer

        var id: String { rawValue }

        var buttonTitle: String {
            switch self {
            case .polish: "Polish"
            case .shorten: "Shorten"
            case .warmer: "Make it warmer"
            }
        }

        var busyTitle: String {
            switch self {
            case .polish: "Polishing…"
            case .shorten: "Shortening…"
            case .warmer: "Warming up…"
            }
        }
    }

    enum AIError: LocalizedError {
        case emptyMessage
        case unavailable
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .emptyMessage:
                "Write a few words first, then tap an AI suggestion."
            case .unavailable:
                "Apple Intelligence isn’t available on this device yet."
            case .failed(let message):
                message
            }
        }
    }

    /// True when the on-device model can run (Apple Intelligence device + ready).
    /// Prefer calling this off the main path when opening UI — the system check can be slow.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            default:
                return false
            }
        }
        #endif
        return false
    }

    static func rewrite(_ text: String, style: Style) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyMessage }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIError.unavailable
            }
            let session = LanguageModelSession(instructions: instructions(for: style))
            let response = try await session.respond(to: trimmed)
            let content = String(response.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw AIError.failed("Apple Intelligence returned an empty suggestion. Try again.")
            }
            return content
        }
        #endif
        throw AIError.unavailable
    }

    private static func instructions(for style: Style) -> String {
        let shared = """
            You help people write sincere thank-you notes on OpenThanks.
            Preserve the original meaning, specific details, and the sender's voice.
            Do not add greetings, sign-offs, quotes, or commentary — return only the rewritten message.
            Stay genuine; never sound fake, salesy, or overly dramatic.
            """
        switch style {
        case .polish:
            return """
            \(shared)
            Rewrite the user's message so it reads clearly and smoothly — polished but not cheesy.
            Fix awkward phrasing while keeping roughly the same length and their natural voice.
            """
        case .shorten:
            return """
            \(shared)
            Rewrite the user's message to be shorter and tighter.
            Cut filler and repetition while keeping the heart of the thank-you and any concrete details.
            Aim for noticeably fewer words — about half the length when possible, without losing sincerity.
            """
        case .warmer:
            return """
            \(shared)
            Rewrite the user's message so it feels warmer and more heartfelt.
            Keep their meaning and approximate length.
            """
        }
    }
}

// MARK: - Voice dictation

/// Apple Speech tap-to-talk for the compose message field (auto punctuation via `addsPunctuation`).
@MainActor
final class AppreciationDictation: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isAvailable = false
    @Published var errorMessage: String?

    /// Text already in the field when the current utterance started (used to splice live partials).
    private(set) var baseText = ""

    /// Latest best transcription for the active utterance (with punctuation when available).
    @Published private(set) var transcript = ""

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private var sessionID = UUID()

    init(locale: Locale = .current) {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        refreshAvailability()
    }

    func refreshAvailability() {
        guard let speechRecognizer else {
            isAvailable = false
            return
        }
        isAvailable = speechRecognizer.isAvailable
    }

    /// Combined message while listening / after a final result: `baseText` + transcript.
    func combinedText(maxLength: Int) -> String {
        let joined = Self.join(base: baseText, addition: transcript)
        if joined.count <= maxLength { return joined }
        return String(joined.prefix(maxLength))
    }

    func toggle(baseText: String) async {
        if isListening {
            finishListening()
        } else {
            await start(baseText: baseText)
        }
    }

    func start(baseText: String) async {
        errorMessage = nil
        guard !isListening else { return }

        guard let speechRecognizer else {
            errorMessage = "Speech recognition isn’t available on this device."
            return
        }
        guard speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available right now. Try again in a moment."
            return
        }

        do {
            try await ensureAuthorized()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        tearDownRecognition(cancelTask: true)

        let session = UUID()
        sessionID = session
        self.baseText = baseText
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Couldn’t access the microphone. Check Settings and try again."
            recognitionRequest = nil
            return
        }

        installInterruptionObserver()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            errorMessage = "Microphone isn’t ready. Try again."
            recognitionRequest = nil
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.completeAfterFinal()
                    }
                }
                if let error {
                    let ns = error as NSError
                    if Self.isBenignSpeechError(ns) {
                        self.completeAfterFinal()
                        return
                    }
                    if self.isListening {
                        self.errorMessage = Self.friendlySpeechError(ns)
                    }
                    self.completeAfterFinal()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Couldn’t start listening. Try again."
            tearDownRecognition(cancelTask: true)
            removeInterruptionObserver()
        }
    }

    /// User tapped stop — end audio so Apple can finalize (with punctuation) without canceling mid-stream.
    func finishListening() {
        guard isListening else { return }
        isListening = false
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private enum AuthError: LocalizedError {
        case micDenied
        case speechDenied

        var errorDescription: String? {
            switch self {
            case .micDenied:
                "Microphone access is off. Enable it in Settings → OpenThanks to speak your appreciation."
            case .speechDenied:
                "Speech recognition is off. Enable it in Settings → OpenThanks to speak your appreciation."
            }
        }
    }

    private func ensureAuthorized() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            break
        case .denied:
            throw AuthError.micDenied
        case .undetermined:
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            }
            if !ok { throw AuthError.micDenied }
        @unknown default:
            throw AuthError.micDenied
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            throw AuthError.speechDenied
        case .notDetermined:
            let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
            }
            if status != .authorized { throw AuthError.speechDenied }
        @unknown default:
            throw AuthError.speechDenied
        }
    }

    private func completeAfterFinal() {
        isListening = false
        tearDownRecognition(cancelTask: false)
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           errorMessage == nil {
            errorMessage = "Didn’t catch that. Tap the mic and try again."
        }
    }

    private func tearDownRecognition(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func installInterruptionObserver() {
        removeInterruptionObserver()
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            guard type == .began else { return }
            Task { @MainActor in
                self?.finishListening()
            }
        }
    }

    private func removeInterruptionObserver() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
    }

    private static func join(base: String, addition: String) -> String {
        let trimmedAddition = addition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddition.isEmpty else { return base }
        if base.isEmpty { return trimmedAddition }
        if base.hasSuffix(" ") || base.hasSuffix("\n") {
            return base + trimmedAddition
        }
        return base + " " + trimmedAddition
    }

    private static func isBenignSpeechError(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain", error.code == 216 || error.code == 1110 {
            return true
        }
        return false
    }

    private static func friendlySpeechError(_ error: NSError) -> String {
        if error.domain == NSURLErrorDomain {
            return "Speech recognition needs a network connection on this device."
        }
        return "Couldn’t finish listening. Try again."
    }
}
