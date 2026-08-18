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

/// Apple Speech tap-to-talk for the compose message field.
/// Pauses become sentence breaks; spoken punctuation and casing are normalized
/// so the result reads like keyboard dictation (Wispr-style).
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
        // Drive stop/start from the visible Listening state so a desynced
        // `wantsListening` flag can't swallow taps.
        if isListening {
            finishListening()
        } else {
            await start(baseText: baseText)
        }
    }

    func start(baseText: String) async {
        errorMessage = nil
        guard !isListening else { return }

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

        // Drop any leftover pause/restart state from a previous attempt.
        restartToken = UUID()
        isRestartingRecognition = false
        tearDownRecognition(cancelTask: true)
        wantsListening = true
        isListening = true
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
    func finishListening() {
        guard wantsListening || isListening else { return }
        wantsListening = false
        isRestartingRecognition = false
        restartToken = UUID()
        commitTranscript()
        baseText = DictationProse.polish(baseText)
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
        baseText = DictationProse.stitch(base: baseText, addition: transcript, finalizeAddition: true)
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

/// Turns raw Apple Speech chunks into readable thank-you prose.
private enum DictationProse {
    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = applySpokenPunctuation(text)
        text = tidyPunctuation(text)
        text = capitalizeStandaloneI(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `finalizeAddition` is true on pause/stop so the finished thought gets a period
    /// and the next phrase starts a new sentence.
    static func stitch(base: String, addition: String, finalizeAddition: Bool) -> String {
        var next = normalize(addition)
        guard !next.isEmpty else { return base }

        if finalizeAddition {
            next = ensureSentenceEnd(next)
        }

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

        if finalizeAddition {
            return ensureSentenceEnd(prefix) + " " + capitalizeLeading(next)
        }

        return prefix + " " + next
    }

    static func polish(_ raw: String) -> String {
        var text = tidyPunctuation(raw)
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

