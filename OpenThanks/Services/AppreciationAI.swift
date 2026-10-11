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
        case warmer

        var id: String { rawValue }

        var buttonTitle: String {
            switch self {
            case .polish: "Polish"
            case .warmer: "Make it warmer"
            }
        }

        var busyTitle: String {
            switch self {
            case .polish: "Polishing…"
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

    /// Fix speech-to-text glitches using the full dictated message (on-device).
    static func cleanupDictation(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyMessage }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard SystemLanguageModel.default.isAvailable else {
                throw AIError.unavailable
            }

            let session = LanguageModelSession(instructions: dictationCleanupInstructions)
            let response = try await session.respond(
                to: dictationCleanupPrompt(trimmed),
                options: GenerationOptions(temperature: 0.2)
            )
            let content = sanitize(String(response.content))
            guard !content.isEmpty else {
                throw AIError.failed("Apple Intelligence returned an empty suggestion. Try again.")
            }
            return content
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

    private static let dictationCleanupInstructions = """
        You clean up voice-dictated thank-you messages on OpenThanks.
        Read the entire message and fix words that do not make sense in context — \
        homophones, merged or split words, obvious speech-recognition mistakes, \
        and stray mid-sentence capitalization after a pause.
        Keep the same meaning, tone, length, names, and details. Do not rewrite for style.
        Keep existing emoji characters. When the speaker clearly asked for an emoji \
        (said "emoji" / "emojis" near a name, e.g. "heart emoji", "fire emoji", \
        "smiley face emoji"), replace that spoken request with the closest matching \
        emoji character — even if the name is slightly misspelled, informal, or not \
        Apple's exact label. Drop the words "emoji"/"emojis" once converted. \
        If the intended emoji is unclear, leave those words as-is.
        Return only the corrected message — no preamble, labels, or commentary.
        """

    private static func dictationCleanupPrompt(_ message: String) -> String {
        """
        This thank-you was dictated by voice. Using the full message for context, \
        fix recognition errors and mid-sentence capitalization while preserving meaning. \
        Convert clear spoken emoji requests (words next to "emoji"/"emojis") into emoji characters.

        Return only the corrected thank-you — no preamble or commentary.

        Message:
        \"\"\"
        \(message)
        \"\"\"
        """
    }

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

/// Apple Speech tap-to-talk for the compose message field.
/// Pauses mid-sentence stay lowercase; stopping runs a full-text cleanup pass.
@MainActor
final class AppreciationDictation: ObservableObject {
    @Published private(set) var isListening = false
    /// Mic permission / audio engine spin-up after the user taps start.
    @Published private(set) var isStarting = false
    /// Finalizing transcript after the user taps stop.
    @Published private(set) var isStopping = false
    @Published private(set) var isAvailable = false
    /// Bumped when committed dictation text changes (pause chunks or stop cleanup).
    @Published private(set) var textEpoch = 0
    @Published var errorMessage: String?

    /// True while the mic control should ignore taps (start-up or stop cleanup).
    var isTransitioning: Bool { isStarting || isStopping }

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
    /// Ignore session-activation interruptions so starting the mic doesn't immediately pause.
    private var ignoreInterruptionsUntil = Date.distantPast

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
        let joined = DictationProse.stitch(base: baseText, addition: transcript, finalizeAddition: false)
        if joined.count <= maxLength { return joined }
        return String(joined.prefix(maxLength))
    }

    func toggle(baseText: String) async {
        // Ignore double-taps while permission / cleanup is in flight.
        guard !isTransitioning else { return }
        // Drive stop/start from the visible Listening state so a desynced
        // `wantsListening` flag can't swallow taps.
        if isListening {
            await finishListening()
        } else {
            await start(baseText: baseText)
        }
    }

    func start(baseText: String) async {
        errorMessage = nil
        guard !isListening, !isStarting, !isStopping else { return }

        guard speechRecognizer != nil else {
            errorMessage = "Speech recognition isn’t available on this device."
            return
        }
        guard speechRecognizer?.isAvailable == true else {
            errorMessage = "Speech recognition isn’t available right now. Try again in a moment."
            return
        }

        isStarting = true
        // Show Starting… immediately — authorization sheets can take a few seconds.
        do {
            try await ensureAuthorized()
        } catch {
            errorMessage = error.localizedDescription
            isStarting = false
            return
        }

        // Drop any leftover pause/restart state from a previous attempt.
        restartToken = UUID()
        isRestartingRecognition = false
        tearDownRecognition(cancelTask: true)
        wantsListening = true
        isListening = true
        isStarting = false
        self.baseText = baseText
        transcript = ""
        lastUtteranceLength = 0
        setIdleTimerDisabled(true)

        do {
            try configureAudioSession()
            beginRecognitionTask()
            try startEngineIfNeeded()
        } catch {
            errorMessage = "Couldn’t access the microphone. Check Settings and try again."
            abortStart()
            return
        }

        // A synchronous Speech callback may already have started a pause-restart.
        if recognitionTask == nil, !isRestartingRecognition {
            errorMessage = "Couldn’t start listening. Try again."
            abortStart()
            return
        }
        ignoreInterruptionsUntil = Date().addingTimeInterval(0.5)
        installInterruptionObserver()
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
    func finishListening() async {
        guard wantsListening || isListening else { return }
        guard !isStopping else { return }
        isStopping = true
        isStarting = false
        wantsListening = false
        isRestartingRecognition = false
        restartToken = UUID()
        commitTranscript()
        baseText = await DictationProse.reconcileFullText(baseText)
        bumpTextEpoch()
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
        isStopping = false
    }

    /// Fold live partials into `baseText` so a late empty final result can't wipe the field.
    private func commitTranscript() {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastUtteranceLength += trimmed.count
        baseText = DictationProse.stitchPauseChunk(base: baseText, addition: transcript)
        transcript = ""
        bumpTextEpoch()
    }

    private func bumpTextEpoch() {
        textEpoch += 1
    }

    private func abortStart() {
        wantsListening = false
        isListening = false
        isStarting = false
        isStopping = false
        isRestartingRecognition = false
        restartToken = UUID()
        setIdleTimerDisabled(false)
        tearDownRecognition(cancelTask: true)
        removeInterruptionObserver()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
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
        // Prefer Apple's networked dictation when available — punctuation and
        // sentence breaks are much closer to keyboard dictation / Wispr.
        recognitionRequest = request
        installTap(for: request)

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.sessionID == session else { return }
                if let result {
                    if self.wantsListening {
                        self.transcript = DictationProse.normalize(result.bestTranscription.formattedString)
                    }
                    if result.isFinal {
                        self.handleUtteranceComplete()
                        return
                    }
                }
                if let error {
                    let ns = error as NSError
                    if Self.isBenignSpeechError(ns) || self.wantsListening {
                        self.handleUtteranceComplete()
                        return
                    }
                    if self.isListening {
                        self.errorMessage = Self.friendlySpeechError(ns)
                    }
                    Task { await self.finishListening() }
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
                if self.recognitionTask == nil {
                    self.errorMessage = "Couldn’t keep listening. Tap the mic to try again."
                    self.abortStart()
                    return
                }
                self.isListening = true
            } catch {
                self.errorMessage = "Couldn’t keep listening. Tap the mic to try again."
                self.abortStart()
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
                guard Date() >= self.ignoreInterruptionsUntil else { return }
                switch type {
                case .began:
                    self.commitTranscript()
                    self.pauseRecognitionForBackground()
                case .ended:
                    let shouldResume = optionsRaw.map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? true
                    if self.wantsListening, shouldResume || self.recognitionTask == nil {
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

    private static func isBenignSpeechError(_ error: NSError) -> Bool {
        if error.domain == "kAFAssistantErrorDomain" {
            // 203 canceled, 209 retry, 216 timeout, 1110 no speech detected.
            return [203, 209, 216, 1101, 1110].contains(error.code)
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

/// Spoken emoji names → characters, applied before dictation text is shown.
///
/// Only phrases that are clearly an emoji request are replaced.
/// "heart", "fire", and "party" stay words unless the speaker says "emoji".
/// Names that are emoji on their own ("smiley face", "thumbs up", "party popper") convert either way.
/// When the speaker says "emoji" / "emojis", near-miss names are fuzzy-matched
/// (speech often won't match Apple's exact label).
enum SpokenEmoji {
    static func apply(to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        var result = text
        for entry in unambiguous.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            result = replace(entry.phrase, in: result, with: entry.emoji, requireEmojiWord: false)
        }
        for entry in named.sorted(by: { $0.phrase.count > $1.phrase.count }) {
            result = replace(entry.phrase, in: result, with: entry.emoji, requireEmojiWord: true)
        }
        // Leftover "… emoji" / "emoji …" that didn't match exactly — guess.
        result = fuzzyReplaceEmojiRequests(in: result)
        return result
    }

    private struct Entry {
        let phrase: String
        let emoji: String
    }

    /// Convert even without the word "emoji".
    private static let unambiguous: [Entry] = [
        .init(phrase: "smiling face with heart eyes", emoji: "😍"),
        .init(phrase: "heart eyes", emoji: "😍"),
        .init(phrase: "smiling face with hearts", emoji: "🥰"),
        .init(phrase: "face with tears of joy", emoji: "😂"),
        .init(phrase: "loudly crying face", emoji: "😭"),
        .init(phrase: "rolling on the floor laughing", emoji: "🤣"),
        .init(phrase: "grinning face", emoji: "😀"),
        .init(phrase: "smiley face", emoji: "😊"),
        .init(phrase: "smiling face", emoji: "😊"),
        .init(phrase: "winking face", emoji: "😉"),
        .init(phrase: "thinking face", emoji: "🤔"),
        .init(phrase: "pleading face", emoji: "🥺"),
        .init(phrase: "crying face", emoji: "😢"),
        .init(phrase: "party popper", emoji: "🎉"),
        .init(phrase: "thumbs up", emoji: "👍"),
        .init(phrase: "thumbs down", emoji: "👎"),
        .init(phrase: "folded hands", emoji: "🙏"),
        .init(phrase: "clapping hands", emoji: "👏"),
        .init(phrase: "raising hands", emoji: "🙌"),
        .init(phrase: "waving hand", emoji: "👋"),
    ]

    /// Convert only when followed by "emoji" / "emojis" — the word alone is normal speech.
    private static let named: [Entry] = [
        .init(phrase: "smiling face with heart eyes", emoji: "😍"),
        .init(phrase: "heart eyes", emoji: "😍"),
        .init(phrase: "smiling face with hearts", emoji: "🥰"),
        .init(phrase: "face with tears of joy", emoji: "😂"),
        .init(phrase: "loudly crying face", emoji: "😭"),
        .init(phrase: "red heart", emoji: "❤️"),
        .init(phrase: "blue heart", emoji: "💙"),
        .init(phrase: "green heart", emoji: "💚"),
        .init(phrase: "yellow heart", emoji: "💛"),
        .init(phrase: "orange heart", emoji: "🧡"),
        .init(phrase: "purple heart", emoji: "💜"),
        .init(phrase: "black heart", emoji: "🖤"),
        .init(phrase: "white heart", emoji: "🤍"),
        .init(phrase: "brown heart", emoji: "🤎"),
        .init(phrase: "broken heart", emoji: "💔"),
        .init(phrase: "two hearts", emoji: "💕"),
        .init(phrase: "growing heart", emoji: "💗"),
        .init(phrase: "sparkling heart", emoji: "💖"),
        .init(phrase: "beating heart", emoji: "💓"),
        .init(phrase: "party popper", emoji: "🎉"),
        .init(phrase: "thumbs up", emoji: "👍"),
        .init(phrase: "thumbs down", emoji: "👎"),
        .init(phrase: "smiley face", emoji: "😊"),
        .init(phrase: "smiling face", emoji: "😊"),
        .init(phrase: "grinning face", emoji: "😀"),
        .init(phrase: "folded hands", emoji: "🙏"),
        .init(phrase: "clapping hands", emoji: "👏"),
        .init(phrase: "raising hands", emoji: "🙌"),
        .init(phrase: "waving hand", emoji: "👋"),
        .init(phrase: "ok hand", emoji: "👌"),
        .init(phrase: "okay hand", emoji: "👌"),
        .init(phrase: "check mark", emoji: "✅"),
        .init(phrase: "checkmark", emoji: "✅"),
        .init(phrase: "heart", emoji: "❤️"),
        .init(phrase: "smiley", emoji: "😊"),
        .init(phrase: "smile", emoji: "😊"),
        .init(phrase: "happy face", emoji: "😊"),
        .init(phrase: "fire", emoji: "🔥"),
        .init(phrase: "flame", emoji: "🔥"),
        .init(phrase: "star", emoji: "⭐"),
        .init(phrase: "sparkles", emoji: "✨"),
        .init(phrase: "sparkle", emoji: "✨"),
        .init(phrase: "rocket", emoji: "🚀"),
        .init(phrase: "party", emoji: "🎉"),
        .init(phrase: "tada", emoji: "🎉"),
        .init(phrase: "confetti", emoji: "🎉"),
        .init(phrase: "clap", emoji: "👏"),
        .init(phrase: "clapping", emoji: "👏"),
        .init(phrase: "pray", emoji: "🙏"),
        .init(phrase: "prayer", emoji: "🙏"),
        .init(phrase: "praying hands", emoji: "🙏"),
        .init(phrase: "thank you", emoji: "🙏"),
        .init(phrase: "thanks", emoji: "🙏"),
        .init(phrase: "cry", emoji: "😢"),
        .init(phrase: "crying", emoji: "😭"),
        .init(phrase: "laugh", emoji: "😂"),
        .init(phrase: "laughing", emoji: "😂"),
        .init(phrase: "kiss", emoji: "😘"),
        .init(phrase: "wink", emoji: "😉"),
        .init(phrase: "wave", emoji: "👋"),
        .init(phrase: "eyes", emoji: "👀"),
        .init(phrase: "hundred", emoji: "💯"),
        .init(phrase: "100", emoji: "💯"),
        .init(phrase: "high five", emoji: "🙌"),
        .init(phrase: "muscle", emoji: "💪"),
        .init(phrase: "flex", emoji: "💪"),
        .init(phrase: "sun", emoji: "☀️"),
        .init(phrase: "moon", emoji: "🌙"),
        .init(phrase: "rainbow", emoji: "🌈"),
        .init(phrase: "flower", emoji: "🌸"),
        .init(phrase: "rose", emoji: "🌹"),
        .init(phrase: "coffee", emoji: "☕"),
        .init(phrase: "hug", emoji: "🤗"),
        .init(phrase: "hugs", emoji: "🤗"),
    ]

    /// Common speech / nickname → canonical phrase tokens before fuzzy match.
    private static let speechAliases: [(String, String)] = [
        ("hart", "heart"),
        ("hurts", "heart"),
        ("hurt", "heart"),
        ("smily", "smiley"),
        ("smilie", "smiley"),
        ("smille", "smile"),
        ("confetti", "party popper"),
        ("celebration", "party"),
        ("celebratory", "party"),
        ("tada", "party"),
        ("ta da", "party"),
        ("highfive", "high five"),
        ("high-five", "high five"),
        ("thankyou", "thank you"),
        ("praying hands", "folded hands"),
        ("prayer hands", "folded hands"),
        ("thumbs-up", "thumbs up"),
        ("thumbs-down", "thumbs down"),
        ("checkmark", "check mark"),
        ("tick", "check mark"),
        ("rofl", "rolling on the floor laughing"),
        ("lol", "laugh"),
        ("lmao", "laugh"),
        ("hearteyes", "heart eyes"),
        ("heart-eyes", "heart eyes"),
    ]

    private static var catalog: [Entry] {
        unambiguous + named
    }

    private static func replace(
        _ phrase: String,
        in text: String,
        with emoji: String,
        requireEmojiWord: Bool
    ) -> String {
        let words = phrase.split(separator: " ").map {
            NSRegularExpression.escapedPattern(for: String($0))
        }
        guard !words.isEmpty else { return text }
        let body = words.joined(separator: #"\s+"#)
        let suffix = requireEmojiWord ? #"\s*,?\s+emojis?"# : #"(?:\s*,?\s+emojis?)?"#
        let pattern = "\\b\(body)\(suffix)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: emoji)
    }

    /// Replace leftover spoken requests like "hart emoji" / "emoji confetti" with a best guess.
    /// Tries longest-to-shortest name spans so "love this heart emoji" still becomes "love this ❤️".
    private static func fuzzyReplaceEmojiRequests(in text: String) -> String {
        guard let emojiWordRegex = try? NSRegularExpression(
            pattern: #"\bemojis?\b"#,
            options: [.caseInsensitive]
        ) else { return text }

        var result = text
        let nsRange = NSRange(result.startIndex..., in: result)
        let matches = emojiWordRegex.matches(in: result, range: nsRange)

        for match in matches.reversed() {
            guard let emojiRange = Range(match.range, in: result) else { continue }

            // Prefer "NAME emoji" (look behind), then "emoji NAME" (look ahead).
            if let resolved = resolveNameBeforeEmoji(in: result, emojiRange: emojiRange)
                ?? resolveNameAfterEmoji(in: result, emojiRange: emojiRange) {
                result.replaceSubrange(resolved.range, with: resolved.emoji)
            }
        }
        return result
    }

    private static func resolveNameBeforeEmoji(
        in text: String,
        emojiRange: Range<String.Index>
    ) -> (range: Range<String.Index>, emoji: String)? {
        let prefix = String(text[..<emojiRange.lowerBound])
        // Optional comma/space already between name and "emoji".
        let trimmedPrefix = prefix.replacingOccurrences(
            of: #"[\s,]+$"#,
            with: "",
            options: .regularExpression
        )
        let words = trimmedPrefix.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }

        let maxWords = min(5, words.count)
        for count in stride(from: maxWords, through: 1, by: -1) {
            let spokenWords = Array(words.suffix(count))
            let spoken = spokenWords.joined(separator: " ")
            guard let emoji = bestGuess(for: spoken) else { continue }

            // Map spoken words back to a range ending at emojiRange.upperBound.
            guard let nameStart = rangeOfTrailingWords(spokenWords, in: trimmedPrefix) else {
                continue
            }
            // `nameStart` is in trimmedPrefix coordinates; map into `text`.
            let absoluteStart = text.index(
                text.startIndex,
                offsetBy: trimmedPrefix.distance(from: trimmedPrefix.startIndex, to: nameStart)
            )
            return (absoluteStart..<emojiRange.upperBound, emoji)
        }
        return nil
    }

    private static func resolveNameAfterEmoji(
        in text: String,
        emojiRange: Range<String.Index>
    ) -> (range: Range<String.Index>, emoji: String)? {
        let afterEmoji = text[emojiRange.upperBound...]
        guard let nameStart = afterEmoji.firstIndex(where: { !$0.isWhitespace && $0 != "," }) else {
            return nil
        }
        let trailing = String(text[nameStart...])
        let words = trailing.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }

        let maxWords = min(5, words.count)
        for count in stride(from: maxWords, through: 1, by: -1) {
            let spokenWords = Array(words.prefix(count))
            let spoken = spokenWords.joined(separator: " ")
            guard let emoji = bestGuess(for: spoken) else { continue }
            guard let nameEnd = rangeOfLeadingWords(spokenWords, in: trailing) else { continue }
            let absoluteEnd = text.index(nameStart, offsetBy: trailing.distance(
                from: trailing.startIndex,
                to: nameEnd
            ))
            return (emojiRange.lowerBound..<absoluteEnd, emoji)
        }
        return nil
    }

    private static func rangeOfTrailingWords(_ words: [String], in text: String) -> String.Index? {
        guard !words.isEmpty else { return nil }
        let pattern = words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#) + #"\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return range.lowerBound
    }

    private static func rangeOfLeadingWords(_ words: [String], in text: String) -> String.Index? {
        guard !words.isEmpty else { return nil }
        let pattern = #"^"# + words
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return range.upperBound
    }

    private static func bestGuess(for spoken: String) -> String? {
        let query = canonicalize(spoken)
        guard !query.isEmpty else { return nil }

        var bestEmoji: String?
        var bestDistance = Int.max
        var bestPhraseLength = 0

        for entry in catalog {
            let phrase = canonicalize(entry.phrase)
            guard !phrase.isEmpty else { continue }
            let distance = editDistance(query, phrase)
            let threshold = max(1, (phrase.count + 2) / 4) // ~25% edits, at least 1
            guard distance <= threshold else { continue }
            // Prefer closer matches; tie-break toward longer (more specific) phrases.
            if distance < bestDistance
                || (distance == bestDistance && phrase.count > bestPhraseLength) {
                bestDistance = distance
                bestPhraseLength = phrase.count
                bestEmoji = entry.emoji
            }
        }

        // Single-token containment after aliasing ("happy" inside "happy face").
        if bestEmoji == nil {
            let tokens = query.split(separator: " ").map(String.init)
            if tokens.count == 1, let token = tokens.first, token.count >= 3 {
                let hit = catalog.first {
                    canonicalize($0.phrase).split(separator: " ").map(String.init).contains(token)
                }
                bestEmoji = hit?.emoji
            }
        }

        return bestEmoji
    }

    private static func canonicalize(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: #"[^\p{L}\p{N}\s']+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop lead-ins that aren't part of the emoji name.
        let leadIns: Set<String> = ["a", "an", "the", "insert", "add", "put", "use", "please"]
        var tokens = s.split(separator: " ").map(String.init)
        while let first = tokens.first, leadIns.contains(first) {
            tokens.removeFirst()
        }
        s = tokens.joined(separator: " ")

        for (from, to) in speechAliases.sorted(by: { $0.0.count > $1.0.count }) {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: from))\\b"
            s = s.replacingOccurrences(of: pattern, with: to, options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        if a == b { return 0 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        let aChars = Array(a)
        let bChars = Array(b)
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            prev = curr
        }
        return prev[bChars.count]
    }
}

/// Turns raw Apple Speech chunks into readable thank-you prose.
enum DictationProse {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = applySpokenPunctuation(text)
        text = SpokenEmoji.apply(to: text)
        text = tidyPunctuation(text)
        text = capitalizeStandaloneI(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Live partial while the mic is still on — don't force sentence breaks.
    static func stitch(base: String, addition: String, finalizeAddition: Bool) -> String {
        if finalizeAddition {
            return stitchPauseChunk(base: base, addition: addition)
        }
        return stitchLive(base: base, addition: addition)
    }

    /// After a pause mid-dictation: keep mid-sentence flow (no forced period / cap).
    static func stitchPauseChunk(base: String, addition: String) -> String {
        var next = normalize(addition)
        guard !next.isEmpty else { return base }

        let prefix = trimTrailingSpaces(base)
        if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return capitalizeLeading(next)
        }
        if prefix.hasSuffix("\n") {
            return prefix + capitalizeLeading(next)
        }
        if endsWithSentencePunctuation(prefix) {
            next = ensureSentenceEnd(next)
            return prefix + " " + capitalizeLeading(next)
        }

        // Mid-sentence pause — lowercase the next chunk.
        return prefix + " " + lowercaseLeading(next)
    }

    private static func stitchLive(base: String, addition: String) -> String {
        let next = normalize(addition)
        guard !next.isEmpty else { return base }

        let prefix = trimTrailingSpaces(base)
        if prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return capitalizeLeading(next)
        }
        if prefix.hasSuffix("\n") {
            return prefix + capitalizeLeading(next)
        }
        if endsWithSentencePunctuation(prefix) {
            return prefix + " " + capitalizeLeading(next)
        }
        if isContinuation(next) {
            return prefix + " " + lowercaseLeading(next)
        }
        return prefix + " " + next
    }

    /// Full pass when dictation stops — punctuation, casing, then context cleanup.
    static func reconcileFullText(_ raw: String) async -> String {
        var text = polish(raw)
        text = fixErroneousMidSentenceCaps(text)
        if AppreciationAI.isAvailable {
            if let cleaned = try? await AppreciationAI.cleanupDictation(text) {
                text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Cleanup can spell an emoji back out; convert again before the field updates.
        return SpokenEmoji.apply(to: text)
    }

    static func polish(_ raw: String) -> String {
        var text = tidyPunctuation(raw)
        text = SpokenEmoji.apply(to: text)
        text = capitalizeStandaloneI(text)
        text = capitalizeSentences(text)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !endsWithSentencePunctuation(trimTrailingSpaces(text)),
           !text.hasSuffix("\n") {
            text = ensureSentenceEnd(trimTrailingSpaces(text))
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let spokenReplacements: [(pattern: String, replacement: String)] = [
        (#"(?i)\bnew paragraph\b"#, "\n\n"),
        (#"(?i)\bnew line\b"#, "\n"),
        (#"(?i)\bquestion mark\b"#, "?"),
        (#"(?i)\bexclamation point\b"#, "!"),
        (#"(?i)\bexclamation mark\b"#, "!"),
        (#"(?i)\bfull stop\b"#, "."),
        (#"(?i)\bdot dot dot\b"#, "…"),
        (#"(?i)\bellipsis\b"#, "…"),
        (#"(?i)\bsemicolon\b"#, ";"),
        (#"(?i)\bcolon\b"#, ":"),
        (#"(?i)\bcomma\b"#, ","),
        (#"(?i)\bperiod\b"#, "."),
    ]

    private static func applySpokenPunctuation(_ text: String) -> String {
        var result = text
        for pair in spokenReplacements {
            result = result.replacingOccurrences(
                of: pair.pattern,
                with: pair.replacement,
                options: .regularExpression
            )
        }
        return result
    }

    private static func tidyPunctuation(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.;:!?…])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([,.;:!?…])([A-Za-z“\"'])"#, with: "$1 $2", options: .regularExpression)
        return s
    }

    private static func capitalizeStandaloneI(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"(?i)\bi'm\b"#, with: "I'm", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bi've\b"#, with: "I've", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bi'll\b"#, with: "I'll", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\bi'd\b"#, with: "I'd", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(^|[\s“\"'(\[])i\b"#, with: "$1I", options: .regularExpression)
        return s
    }

    private static func capitalizeSentences(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var chars = Array(text)
        var capitalizeNext = true
        for i in chars.indices {
            let ch = chars[i]
            if ch.isNewline {
                capitalizeNext = true
                continue
            }
            if capitalizeNext, ch.isLetter {
                chars[i] = Character(ch.uppercased())
                capitalizeNext = false
                continue
            }
            if ch == "." || ch == "!" || ch == "?" || ch == "…" {
                capitalizeNext = true
            } else if !ch.isWhitespace && ch != "\"" && ch != "“" && ch != "'" {
                capitalizeNext = false
            }
        }
        return String(chars)
    }

    private static func capitalizeLeading(_ text: String) -> String {
        guard let index = text.firstIndex(where: { $0.isLetter || $0.isNumber }) else { return text }
        var chars = Array(text)
        let offset = text.distance(from: text.startIndex, to: index)
        if chars[offset].isLetter {
            chars[offset] = Character(chars[offset].uppercased())
        }
        return String(chars)
    }

    /// Speech often capitalizes the word after a mid-sentence pause — fix before AI/heuristics.
    private static func fixErroneousMidSentenceCaps(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var sentenceStart = true

        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch.isNewline {
                sentenceStart = true
                result.append(ch)
                index = text.index(after: index)
                continue
            }

            if ch.isLetter {
                let wordStart = index
                var wordEnd = index
                while wordEnd < text.endIndex {
                    let c = text[wordEnd]
                    if c.isLetter || c == "'" { wordEnd = text.index(after: wordEnd) } else { break }
                }
                let word = String(text[wordStart..<wordEnd])
                var wordOut = word
                if !sentenceStart,
                   let first = word.first,
                   first.isUppercase,
                   word != "I",
                   !word.hasPrefix("I'"),
                   let prev = lastSignificantCharacter(in: result),
                   prev.isLowercase {
                    wordOut = word.prefix(1).lowercased() + word.dropFirst()
                }
                result.append(contentsOf: wordOut)
                index = wordEnd
                sentenceStart = false
                continue
            }

            if ".!?…".contains(ch) {
                sentenceStart = true
            }
            result.append(ch)
            index = text.index(after: index)
        }
        return result
    }

    private static func lastSignificantCharacter(in text: String) -> Character? {
        for ch in text.reversed() where !ch.isWhitespace {
            return ch
        }
        return nil
    }

    private static func lowercaseLeading(_ text: String) -> String {
        guard let index = text.firstIndex(where: \.isLetter) else { return text }
        let word = firstWord(text).lowercased()
        if word == "i" || word.hasPrefix("i'") { return text }
        var chars = Array(text)
        let offset = text.distance(from: text.startIndex, to: index)
        chars[offset] = Character(chars[offset].lowercased())
        return String(chars)
    }

    private static func ensureSentenceEnd(_ text: String) -> String {
        let trimmed = trimTrailingSpaces(text)
        guard !trimmed.isEmpty else { return trimmed }
        if endsWithSentencePunctuation(trimmed) || trimmed.hasSuffix(":") { return trimmed }
        if trimmed.hasSuffix(",") || trimmed.hasSuffix(";") {
            return String(trimmed.dropLast()) + "."
        }
        return trimmed + "."
    }

    private static func endsWithSentencePunctuation(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        return CharacterSet(charactersIn: ".!?…").contains(last)
    }

    private static func trimTrailingSpaces(_ text: String) -> String {
        var end = text.endIndex
        while end > text.startIndex {
            let prev = text.index(before: end)
            if text[prev] == " " || text[prev] == "\t" {
                end = prev
            } else {
                break
            }
        }
        return String(text[..<end])
    }

    private static let continuationWords: Set<String> = [
        "and", "but", "or", "nor", "so", "yet",
        "because", "since", "although", "though", "unless",
        "which", "that", "who", "whom", "whose",
        "when", "while", "if", "then", "also",
        "plus", "with", "without", "for",
    ]

    private static func isContinuation(_ text: String) -> Bool {
        continuationWords.contains(firstWord(text).lowercased())
    }

    private static func firstWord(_ text: String) -> String {
        let scalars = text.unicodeScalars.drop(while: { CharacterSet.whitespacesAndNewlines.contains($0) })
        let word = scalars.prefix { CharacterSet.letters.contains($0) || $0 == "'" }
        return String(String.UnicodeScalarView(word))
    }
}

