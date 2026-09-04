import Foundation
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

    private func handleCreate(_ request: WatchRelay.CreateRequest) async -> WatchRelay.CreateReply {
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

        // Run the same dictation cleanup as iOS compose before saving.
        let cleaned = await DictationProse.reconcileFullText(message)
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
            let transcript: String
            do {
                transcript = try await Self.transcribeAudioFile(at: url, preferOnDevice: true)
            } catch {
                // On-device models may be missing — fall back to cloud once.
                transcript = try await Self.transcribeAudioFile(at: url, preferOnDevice: false)
            }
            let request = WatchRelay.CreateRequest(
                id: draftId,
                message: transcript,
                recipient: nil
            )
            return await handleCreate(request)
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

    private static func transcribeAudioFile(at url: URL, preferOnDevice: Bool = true) async throws -> String {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        // Prefer on-device when available — more reliable while iPhone is backgrounded.
        if preferOnDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            request.requiresOnDeviceRecognition = false
        }

        let text: String = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    final class Box {
                        var task: SFSpeechRecognitionTask?
                        var settled = false
                    }
                    let box = Box()
                    box.task = recognizer.recognitionTask(with: request) { result, error in
                        guard !box.settled else { return }
                        if let error {
                            box.settled = true
                            cont.resume(throwing: error)
                            return
                        }
                        guard let result, result.isFinal else { return }
                        box.settled = true
                        cont.resume(returning: result.bestTranscription.formattedString)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(40))
                throw TranscriptionError.timedOut
            }
            guard let value = try await group.next() else {
                throw TranscriptionError.unavailable
            }
            group.cancelAll()
            return value
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.empty }
        return trimmed
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
