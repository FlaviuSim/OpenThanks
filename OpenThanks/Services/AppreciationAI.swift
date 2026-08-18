import AVFoundation
import Foundation
import Speech
import UIKit

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

            let first = try await generateRewrite(
                message: trimmed,
                style: style,
                forceChange: false,
                temperature: 0.85
            )
            if !isEffectivelyUnchanged(original: trimmed, candidate: first) {
                return first
            }

            // On-device models often echo short thanks unchanged — push harder once.
            let second = try await generateRewrite(
                message: trimmed,
                style: style,
                forceChange: true,
                temperature: 1.0
            )
            if !isEffectivelyUnchanged(original: trimmed, candidate: second) {
                return second
            }

            throw AIError.failed("Couldn't find a different wording. Try adding a bit more detail, then tap again.")
        }
        #endif
        throw AIError.unavailable
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func generateRewrite(
        message: String,
        style: Style,
        forceChange: Bool,
        temperature: Double
    ) async throws -> String {
        let session = LanguageModelSession(instructions: instructions(for: style, forceChange: forceChange))
        let options = GenerationOptions(temperature: temperature)
        let response = try await session.respond(
            to: userPrompt(for: style, message: message, forceChange: forceChange),
            options: options
        )
        let content = sanitize(String(response.content))
        guard !content.isEmpty else {
            throw AIError.failed("Apple Intelligence returned an empty suggestion. Try again.")
        }
        return content
    }
    #endif

    /// Strip model wrappers and lead-in commentary so only the thank-you remains.
    private static func sanitize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var previous = ""
        while text != previous {
            previous = text
            text = unwrapQuotes(text)
            text = stripLeadIn(text)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func unwrapQuotes(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers: [(Character, Character)] = [
            ("\"", "\""), ("'", "'"), ("\u{201c}", "\u{201d}"), ("\u{2018}", "\u{2019}"),
        ]
        for (open, close) in wrappers {
            if text.count >= 2, text.first == open, text.last == close {
                text = String(text.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }

    /// Drops “Here is a revised version of your message:” and similar preambles.
    private static func stripLeadIn(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.first, isLeadInLine(first) {
            return lines.dropFirst().joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = leadInPrefixRange(in: text) {
            return String(text[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func isLeadInLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        let starters = [
            "here is a revised",
            "here's a revised",
            "here is the revised",
            "here's the revised",
            "here is a rewritten",
            "here's a rewritten",
            "here is the rewritten",
            "here's the rewritten",
            "here is a polished",
            "here's a polished",
            "here is a warmer",
            "here is a shorter",
            "here is an updated",
            "here is your",
            "here's your",
            "here is the message",
            "here's the message",
            "revised version of your",
            "rewritten message",
            "rewritten:",
            "revised:",
            "sure, here",
            "sure here",
            "of course, here",
            "below is",
            "i've rewritten",
            "i have rewritten",
            "i rewrote",
            "i've polished",
        ]
        if starters.contains(where: { lower.hasPrefix($0) }) { return true }
        // Short label line ending with a colon, e.g. "Rewritten message:"
        if trimmed.count <= 90, trimmed.hasSuffix(":"),
           lower.contains("revis") || lower.contains("rewrit") || lower.contains("version")
            || lower.contains("message") || lower.contains("here") {
            return true
        }
        return false
    }

    private static func leadInPrefixRange(in text: String) -> Range<String.Index>? {
        let pattern = #"(?i)^(sure[,!]?\s+|of course[,!]?\s+|okay[,!]?\s+|ok[,!]?\s+)?(here'?s|here is|this is|below is)\s+(a |the )?(revised|rewritten|updated|polished|warmer|shortened|improved)\s+(version|message|note|text)?(\s+of\s+(your |the )?(message|note|appreciation|text))?\s*[:.\-–—]\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, range: full),
              let range = Range(match.range, in: text),
              range.lowerBound == text.startIndex else { return nil }
        return range
    }

    private static func isEffectivelyUnchanged(original: String, candidate: String) -> Bool {
        normalizeForCompare(original) == normalizeForCompare(candidate)
    }

    private static func normalizeForCompare(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
    }

    private static func userPrompt(for style: Style, message: String, forceChange: Bool) -> String {
        let verb: String
        switch style {
        case .polish: verb = "Polish"
        case .shorten: verb = "Shorten"
        case .warmer: verb = "Warm up"
        }
        let mustChange = forceChange
            ? " You MUST change the wording — do not return the same sentences."
            : " Change the wording so the result is clearly different from the input."
        return """
        \(verb) this thank-you message.\(mustChange)
        Return only the rewritten thank-you — no preamble, labels, or commentary.
        Do not start with phrases like "Here is a revised version of your message".

        Message:
        \"\"\"
        \(message)
        \"\"\"
        """
    }

    private static func instructions(for style: Style, forceChange: Bool = false) -> String {
        let forceLine = forceChange
            ? "Critical: the output must NOT be identical or nearly identical to the input. Rephrase every sentence."
            : "The rewritten message must be clearly different from the input — never copy it verbatim."
        let shared = """
            You help people write sincere thank-you notes on OpenThanks.
            Keep the same meaning and any concrete details (names, moments, specifics).
            Do not add greetings, sign-offs, quotes, labels, or commentary — return only the rewritten message.
            Never open with "Here is a revised version", "Here's the rewritten message", or any similar intro.
            Stay genuine; never sound fake, salesy, or overly dramatic.
            \(forceLine)
            """
        switch style {
        case .polish:
            return """
            \(shared)
            Rewrite so it reads clearly and smoothly — polished but not cheesy.
            Fix awkward phrasing and tighten word choice while keeping roughly the same length.
            """
        case .shorten:
            return """
            \(shared)
            Make it noticeably shorter and tighter — about half the words when possible.
            Cut filler and repetition; keep the heart of the thank-you and concrete details.
            """
        case .warmer:
            return """
            \(shared)
            Make it warmer and more heartfelt with kinder, more personal phrasing.
            Keep roughly the same length; do not just add exclamation points.
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

    /// Length of speech committed in this tap-to-talk session (for analytics).
    private(set) var lastUtteranceLength = 0

    private let speechRecognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var interruptionObserver: NSObjectProtocol?
    private var sessionID = UUID()
    /// User wants dictation on until they tap stop — keep restarting after pauses.
    private var wantsListening = false
    /// Avoid stacking restart work while a new Speech task is spinning up.
    private var isRestartingRecognition = false
    private var audioTapInstalled = false
    /// Invalidates in-flight restart work after stop / a newer restart.
    private var restartToken = UUID()

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
        if wantsListening || isListening {
            finishListening()
        } else {
            await start(baseText: baseText)
        }
    }

    func start(baseText: String) async {
        errorMessage = nil
        guard !wantsListening, !isListening else { return }

        guard speechRecognizer != nil else {
            errorMessage = "Speech recognition isn’t available on this device."
            return
        }
        guard speechRecognizer?.isAvailable == true else {
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
        wantsListening = true
        self.baseText = baseText
        transcript = ""
        lastUtteranceLength = 0
        setIdleTimerDisabled(true)
        installInterruptionObserver()

        do {
            try configureAudioSession()
            beginRecognitionTask()
            try startEngineIfNeeded()
        } catch {
            errorMessage = "Couldn’t access the microphone. Check Settings and try again."
            abortStart()
            return
        }

        isListening = recognitionTask != nil
        if !isListening {
            errorMessage = "Couldn’t start listening. Try again."
            abortStart()
        }
    }

    /// Keep the screen awake while dictating; resume after the app comes back.
    func handleAppDidBecomeActive() {
        guard wantsListening else { return }
        setIdleTimerDisabled(true)
        if recognitionTask == nil {
            restartRecognitionKeepingAudio()
        }
    }

    /// Commit spoken text if the screen locks or the app leaves the foreground.
    func handleAppWillResignActive() {
        setIdleTimerDisabled(false)
        guard wantsListening else { return }
        commitTranscript()
        pauseRecognitionForBackground()
    }

    /// User tapped stop — end audio so Apple can finalize (with punctuation) without canceling mid-stream.
    func finishListening() {
        guard wantsListening || isListening else { return }
        wantsListening = false
        isRestartingRecognition = false
        restartToken = UUID()
        commitTranscript()
        isListening = false
        setIdleTimerDisabled(false)
        recognitionRequest?.endAudio()
        tearDownRecognition(cancelTask: false)
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           errorMessage == nil {
            errorMessage = "Didn’t catch that. Tap the mic and try again."
        }
    }

    /// Fold live partials into `baseText` so a late empty final result can't wipe the field.
    private func commitTranscript() {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastUtteranceLength += trimmed.count
        baseText = Self.join(base: baseText, addition: transcript)
        transcript = ""
    }

    private func abortStart() {
        wantsListening = false
        isListening = false
        isRestartingRecognition = false
        restartToken = UUID()
        setIdleTimerDisabled(false)
        tearDownRecognition(cancelTask: true)
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        // `.spokenAudio` is less aggressive about ending on silence than `.measurement`.
        try audioSession.setCategory(.record, mode: .spokenAudio, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startEngineIfNeeded() throws {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "AppreciationDictation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone isn’t ready. Try again."]
            )
        }
        if !audioEngine.isRunning {
            audioEngine.prepare()
            try audioEngine.start()
        }
    }

    private func installTap(for request: SFSpeechAudioBufferRecognitionRequest) {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        if audioTapInstalled {
            inputNode.removeTap(onBus: 0)
            audioTapInstalled = false
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioTapInstalled = true
    }

    private func beginRecognitionTask() {
        guard wantsListening, let speechRecognizer else { return }

        sessionID = UUID()
        let session = sessionID
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request
        installTap(for: request)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                if let result {
                    if self.wantsListening {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if result.isFinal {
                        self.handleUtteranceComplete()
                        return
                    }
                }
                if let error {
                    let ns = error as NSError
                    if Self.isBenignSpeechError(ns) {
                        self.handleUtteranceComplete()
                        return
                    }
                    if self.wantsListening {
                        self.errorMessage = Self.friendlySpeechError(ns)
                    }
                    self.finishListening()
                }
            }
        }
    }

    /// Apple Speech finalizes after a pause. Commit that chunk and keep listening until the user taps stop.
    private func handleUtteranceComplete() {
        commitTranscript()
        guard wantsListening else {
            isListening = false
            tearDownRecognition(cancelTask: false)
            removeInterruptionObserver()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        restartRecognitionKeepingAudio()
    }

    private func restartRecognitionKeepingAudio() {
        guard wantsListening, !isRestartingRecognition else { return }
        isRestartingRecognition = true
        sessionID = UUID()
        let token = UUID()
        restartToken = token
        recognitionRequest?.endAudio()
        recognitionTask = nil
        recognitionRequest = nil

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard self.restartToken == token else { return }
            self.isRestartingRecognition = false
            guard self.wantsListening else { return }
            do {
                try self.configureAudioSession()
                self.beginRecognitionTask()
                try self.startEngineIfNeeded()
                self.isListening = self.recognitionTask != nil
            } catch {
                self.errorMessage = "Couldn’t keep listening. Tap the mic to try again."
                self.finishListening()
            }
        }
    }

    private func pauseRecognitionForBackground() {
        sessionID = UUID()
        isRestartingRecognition = false
        restartToken = UUID()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioTapInstalled = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private func tearDownRecognition(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if audioTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioTapInstalled = false
        }
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func setIdleTimerDisabled(_ disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled
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
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                guard let self else { return }
                switch type {
                case .began:
                    self.commitTranscript()
                    self.pauseRecognitionForBackground()
                case .ended:
                    let shouldResume = optionsRaw.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? true
                    if self.wantsListening, shouldResume {
                        self.restartRecognitionKeepingAudio()
                    }
                default:
                    break
                }
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
