import Foundation
import AVFoundation
import Speech
import UIKit
import WatchConnectivity

/// iPhone side of Watch Connectivity: pushes auth context and creates appreciations.
/// Safe with no Watch paired — activates once, then no-ops until a Watch is available.
@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private weak var auth: AuthService?
    private var didRequestActivation = false
    /// Last create reply pushed to the Watch — re-included when auth context updates
    /// so `updateApplicationContext` does not wipe an in-flight “Saving…” waiter.
    private var lastCreateResultData: Data?
    private var voiceBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// True after activation completes with a paired Watch that has our companion installed.
    private(set) var isWatchReady = false

    func activate(auth: AuthService?) {
        if let auth {
            self.auth = auth
        }
        // Simulator WCSession without a paired Watch floods logs with
        // "pairingIDs no longer match" / "WCSession is not paired" and is
        // useless for phone-only runs. Real devices (and Watch testing) still activate.
        #if targetEnvironment(simulator)
        return
        #else
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }

        // Request activation at most once until the session deactivates.
        switch session.activationState {
        case .notActivated where !didRequestActivation:
            didRequestActivation = true
            session.activate()
        case .activated:
            refreshWatchReadiness(session)
            if self.auth != nil {
                pushAuthContext()
            }
        default:
            break
        }
        #endif
    }

    func pushAuthContext() {
        #if targetEnvironment(simulator)
        return
        #else
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else {
            isWatchReady = false
            return
        }
        isWatchReady = true

        let context: WatchRelay.AuthContext
        if let userId = auth?.userId {
            context = WatchRelay.AuthContext(
                isSignedIn: true,
                displayName: auth?.currentProfile?.displayName,
                userId: userId.uuidString
            )
        } else {
            context = .signedOut
        }

        guard let data = WatchRelay.encode(context) else { return }
        var payload: [String: Any] = [WatchRelay.authContextKey: data]
        // Keep outstanding create replies so Watch “Saving…” waiters still resolve.
        if let lastCreateResultData {
            payload[WatchRelay.createResultKey] = lastCreateResultData
        }
        do {
            try session.updateApplicationContext(payload)
        } catch {
            // Non-fatal — Watch will retry when reachable / next activate.
            #if DEBUG
            print("WatchConnectivity auth context failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    private func refreshWatchReadiness(_ session: WCSession) {
        isWatchReady = session.isPaired && session.isWatchAppInstalled
    }

    // MARK: - Create

    private func handleCreate(
        _ request: WatchRelay.CreateRequest,
        lightCleanup: Bool = false
    ) async -> WatchRelay.CreateReply {
        guard let auth, let userId = auth.userId else {
            return .failure(
                draftId: request.id,
                code: "notSignedIn",
                message: "Sign in on iPhone to save thanks."
            )
        }

        let message = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return .failure(
                draftId: request.id,
                code: "emptyMessage",
                message: "Write a short note first."
            )
        }

        // Watch voice uses lightCleanup; text drafts get full reconcile.
        // Guard against AI cleanup returning a stub of a long message.
        let cleaned: String
        if lightCleanup {
            cleaned = DictationProse.polish(message)
        } else {
            let reconciled = await DictationProse.reconcileFullText(message)
            cleaned = (reconciled.count < max(12, message.count / 4))
                ? DictationProse.polish(message)
                : reconciled
        }
        let clipped = String(cleaned.prefix(1_500))
        let contact = Self.parseRecipient(request.recipient)
        let new = NewGratitude(
            authorId: userId,
            message: clipped,
            recipientEmail: contact.email,
            recipientPhone: contact.phone,
            recipientName: contact.name,
            recipientId: nil,
            visibility: GratitudeVisibility.public.rawValue,
            mediaUrl: nil,
            mediaType: nil,
            source: "watch"
        )

        do {
            let created = try await GratitudeService.create(new)
            let recipientKind: String = {
                if contact.email != nil { return "email" }
                if contact.phone != nil { return "phone" }
                if !(contact.name ?? "").isEmpty { return "name" }
                return "none"
            }()
            Analytics.appreciationSubmitted(
                hasMedia: false,
                messageLength: clipped.count,
                hasRecipient: recipientKind != "none",
                toMember: false,
                recipientType: recipientKind,
                visibility: GratitudeVisibility.public.rawValue,
                source: "watch"
            )
            await WidgetSnapshotRefresher.refresh(
                displayName: auth.currentProfile?.displayName,
                userId: userId,
                email: auth.currentProfile?.email,
                phone: auth.currentProfile?.phone
            )
            await StreakLiveActivityController.appreciationDidSend(userId: userId)
            let reply = WatchRelay.CreateReply.success(draftId: request.id, gratitudeId: created.id)
            publishCreateResult(reply)
            return reply
        } catch {
            Analytics.appreciationFailed(error: error.localizedDescription, source: "watch")
            let reply = WatchRelay.CreateReply.failure(
                draftId: request.id,
                code: "network",
                message: error.localizedDescription
            )
            publishCreateResult(reply)
            return reply
        }
    }

    /// Watch recorded audio → speech-to-text → same create path.
    private func handleVoiceFile(at url: URL, draftId: UUID) async -> WatchRelay.CreateReply {
        do {
            let duration = await Self.audioDurationSeconds(at: url)
            // Long clips: prefer cloud; on-device often keeps only the last phrase.
            let preferOnDevice = duration > 0 && duration < 28
            let transcript: String
            do {
                transcript = try await Self.transcribeAudioFile(at: url, preferOnDevice: preferOnDevice)
            } catch {
                transcript = try await Self.transcribeAudioFile(at: url, preferOnDevice: false)
            }
            let request = WatchRelay.CreateRequest(
                id: draftId,
                message: transcript,
                recipient: nil
            )
            return await handleCreate(request, lightCleanup: true)
        } catch {
            let reply = WatchRelay.CreateReply.failure(
                draftId: draftId,
                code: "transcription",
                message: error.localizedDescription
            )
            publishCreateResult(reply)
            return reply
        }
    }

    /// Transcribe a Watch voice file. Long clips are split — SFSpeech often only
    /// returns the last utterance for multi-minute URL requests.
    private static func transcribeAudioFile(at url: URL, preferOnDevice: Bool = true) async throws -> String {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        let duration = await audioDurationSeconds(at: url)
        let chunkLimit: Double = 45
        if duration <= chunkLimit + 5 {
            return try await transcribeSingleFile(at: url, preferOnDevice: preferOnDevice, timeoutSeconds: 120)
        }

        let chunkURLs = try await splitAudio(at: url, chunkSeconds: chunkLimit)
        defer {
            for chunk in chunkURLs {
                try? FileManager.default.removeItem(at: chunk)
            }
        }

        var combined = ""
        for chunk in chunkURLs {
            let piece = try await transcribeSingleFile(
                at: chunk,
                preferOnDevice: preferOnDevice,
                timeoutSeconds: 90
            )
            combined = DictationProse.stitchPauseChunk(base: combined, addition: piece)
        }
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.empty }
        return trimmed
    }

    private static func transcribeSingleFile(
        at url: URL,
        preferOnDevice: Bool,
        timeoutSeconds: Double
    ) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        // Partials keep a growing cumulative string; finals alone can be per-phrase.
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if preferOnDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }

        final class Box: @unchecked Sendable {
            var task: SFSpeechRecognitionTask?
            var best = ""
            var settled = false
            var finishWork: DispatchWorkItem?
        }
        let box = Box()

        let text: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    let finish: (Result<String, Error>) -> Void = { result in
                        guard !box.settled else { return }
                        box.settled = true
                        box.finishWork?.cancel()
                        box.task?.cancel()
                        cont.resume(with: result)
                    }

                    box.task = recognizer.recognitionTask(with: request) { result, error in
                        if let result {
                            let formatted = result.bestTranscription.formattedString
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            if formatted.count >= box.best.count {
                                box.best = formatted
                            }
                        }

                        if let error {
                            let best = box.best.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !best.isEmpty {
                                finish(.success(best))
                            } else {
                                finish(.failure(error))
                            }
                            return
                        }

                        guard let result, result.isFinal else { return }
                        // Debounce — long files emit multiple finals; keep the longest.
                        box.finishWork?.cancel()
                        let work = DispatchWorkItem {
                            let best = box.best.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !best.isEmpty {
                                finish(.success(best))
                            } else {
                                finish(.failure(TranscriptionError.empty))
                            }
                        }
                        box.finishWork = work
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.45, execute: work)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                let best = box.best.trimmingCharacters(in: .whitespacesAndNewlines)
                if !best.isEmpty { return best }
                throw TranscriptionError.timedOut
            }
            guard let value = try await group.next() else {
                throw TranscriptionError.unavailable
            }
            group.cancelAll()
            box.finishWork?.cancel()
            box.task?.cancel()
            return value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.empty }
        return trimmed
    }

    private static func audioDurationSeconds(at url: URL) async -> Double {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? seconds : 0
        } catch {
            return 0
        }
    }

    private static func splitAudio(at url: URL, chunkSeconds: Double) async throws -> [URL] {
        let total = await audioDurationSeconds(at: url)
        guard total > 0 else { return [url] }

        var urls: [URL] = []
        var start: Double = 0
        var index = 0
        while start < total - 0.25 {
            let end = min(start + chunkSeconds, total)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("watch-voice-chunk-\(UUID().uuidString)-\(index).m4a")
            try await exportAudioSlice(source: url, start: start, end: end, to: dest)
            urls.append(dest)
            start = end
            index += 1
        }
        return urls.isEmpty ? [url] : urls
    }

    private static func exportAudioSlice(
        source: URL,
        start: Double,
        end: Double,
        to dest: URL
    ) async throws {
        try? FileManager.default.removeItem(at: dest)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscriptionError.unavailable
        }
        session.outputURL = dest
        session.outputFileType = .m4a
        let startTime = CMTime(seconds: start, preferredTimescale: 600)
        let duration = CMTime(seconds: max(0.1, end - start), preferredTimescale: 600)
        session.timeRange = CMTimeRange(start: startTime, duration: duration)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                let status = session.status
                let exportError = session.error
                switch status {
                case .completed:
                    cont.resume()
                case .failed, .cancelled:
                    cont.resume(throwing: exportError ?? TranscriptionError.unavailable)
                default:
                    cont.resume(throwing: TranscriptionError.unavailable)
                }
            }
        }
    }

    private enum TranscriptionError: LocalizedError {
        case notAuthorized
        case unavailable
        case empty
        case timedOut
        case copyFailed

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Allow Speech Recognition on iPhone to save Watch thanks."
            case .unavailable:
                return "Speech recognition isn’t available right now."
            case .empty:
                return "Didn’t catch that — try speaking a bit longer."
            case .timedOut:
                return "Transcription timed out — keep iPhone unlocked nearby and try again."
            case .copyFailed:
                return "Couldn’t read the recording from Watch."
            }
        }
    }

    private func publishCreateResult(_ reply: WatchRelay.CreateReply) {
        guard WCSession.isSupported(),
              let replyData = WatchRelay.encode(reply) else { return }
        lastCreateResultData = replyData

        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return }

        var context: [String: Any] = [WatchRelay.createResultKey: replyData]
        let authContext = WatchRelay.AuthContext(
            isSignedIn: auth?.userId != nil,
            displayName: auth?.currentProfile?.displayName,
            userId: auth?.userId?.uuidString
        )
        if let authData = WatchRelay.encode(authContext) {
            context[WatchRelay.authContextKey] = authData
        }
        try? session.updateApplicationContext(context)

        // Queued delivery — survives better than application context alone.
        if let userInfo = WatchRelay.createResultUserInfo(reply) {
            session.transferUserInfo(userInfo)
        }

        // Fast path when Watch is reachable right now.
        if session.isReachable, let userInfo = WatchRelay.createResultUserInfo(reply) {
            session.sendMessage(userInfo, replyHandler: nil, errorHandler: { _ in })
        }
    }

    private func beginVoiceBackgroundTask() {
        endVoiceBackgroundTask()
        voiceBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "watch-voice") { [weak self] in
            Task { @MainActor in
                self?.endVoiceBackgroundTask()
            }
        }
    }

    private func endVoiceBackgroundTask() {
        guard voiceBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(voiceBackgroundTask)
        voiceBackgroundTask = .invalid
    }

    private static func parseRecipient(_ raw: String?)
        -> (name: String?, email: String?, phone: String?) {
        guard let raw else { return (nil, nil, nil) }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, nil) }
        if WatchRelay.looksLikeEmail(value) {
            return (nil, AuthService.normalizedEmail(value), nil)
        }
        if value.hasPrefix("@") {
            let handle = String(value.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return (handle.isEmpty ? nil : handle, nil, nil)
        }
        let digits = value.filter(\.isNumber)
        if digits.count >= 7 && value.allSatisfy({ "+()- 0123456789".contains($0) }) {
            let e164 = value.hasPrefix("+") ? "+" + digits : "+1" + digits
            return (nil, nil, e164)
        }
        return (value, nil, nil)
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if activationState == .activated {
                refreshWatchReadiness(session)
                pushAuthContext()
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            refreshWatchReadiness(session)
            pushAuthContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            didRequestActivation = false
            isWatchReady = false
            session.activate()
            didRequestActivation = true
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            let reply = await processMessage(message)
            replyHandler(reply)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            _ = await processMessage(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            _ = await processMessage(userInfo)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let fileURL = file.fileURL
        let metadata = file.metadata ?? [:]
        let draftId = (metadata[WatchRelay.voiceDraftIdKey] as? String).flatMap { UUID(uuidString: $0) }
            ?? UUID()
        let action = metadata[WatchRelay.actionKey] as? String
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("watch-voice-\(draftId.uuidString).m4a")
        try? FileManager.default.removeItem(at: temp)

        do {
            try FileManager.default.copyItem(at: fileURL, to: temp)
        } catch {
            Task { @MainActor in
                let reply = WatchRelay.CreateReply.failure(
                    draftId: draftId,
                    code: "copyFailed",
                    message: TranscriptionError.copyFailed.localizedDescription
                )
                publishCreateResult(reply)
            }
            return
        }

        Task { @MainActor in
            beginVoiceBackgroundTask()
            defer {
                try? FileManager.default.removeItem(at: temp)
                endVoiceBackgroundTask()
            }
            guard action == WatchRelay.Action.createFromVoice.rawValue else { return }
            _ = await handleVoiceFile(at: temp, draftId: draftId)
        }
    }

    @MainActor
    private func processMessage(_ message: [String: Any]) async -> [String: Any] {
        let action = message[WatchRelay.actionKey] as? String
        switch action {
        case WatchRelay.Action.ping.rawValue:
            pushAuthContext()
            return ["ok": true]
        case WatchRelay.Action.createAppreciation.rawValue:
            guard let request = WatchRelay.decode(
                WatchRelay.CreateRequest.self,
                fromAny: message[WatchRelay.payloadKey]
            ) else {
                return replyDict(
                    .failure(
                        draftId: UUID(),
                        code: "badRequest",
                        message: "Couldn't read that draft."
                    )
                )
            }
            let result = await handleCreate(request)
            return replyDict(result)
        default:
            return ["ok": false, "errorCode": "unknownAction"]
        }
    }

    private func replyDict(_ reply: WatchRelay.CreateReply) -> [String: Any] {
        guard let data = WatchRelay.encode(reply) else {
            return ["ok": false, "errorCode": "encodeFailed"]
        }
        return [
            "ok": reply.ok,
            WatchRelay.payloadKey: data,
        ]
    }
}
