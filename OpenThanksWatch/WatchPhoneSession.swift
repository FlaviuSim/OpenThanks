import Foundation
import Observation
import WatchConnectivity

/// Watch-side WCSession client: auth context, create + local queue.
@Observable
@MainActor
final class WatchPhoneSession: NSObject {
    static let shared = WatchPhoneSession()

    var auth = WatchRelay.AuthContext.signedOut
    var isReachable = false
    var isActivated = false
    var lastError: String?
    var pendingComposeFocus = false
    /// When true, compose should start dictation immediately (no suggestion chips).
    var pendingAutoRecord = false
    /// Draft ids currently sending (interactive or flush).
    private(set) var sendingIds: Set<UUID> = []

    private var didActivate = false

    override init() {
        super.init()
        activate()
    }

    /// Open compose; optionally jump straight into voice recording.
    func requestCompose(autoRecord: Bool) {
        pendingComposeFocus = true
        pendingAutoRecord = autoRecord
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastError = "Watch Connectivity isn't available."
            return
        }
        let session = WCSession.default
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        } else {
            isActivated = true
            isReachable = session.isReachable
            ingestApplicationContext(session.receivedApplicationContext)
        }
        didActivate = true
    }

    var isSignedIn: Bool { auth.isSignedIn }

    var queuedCount: Int { WatchDraftQueue.all().count }

    /// Records a thanks and saves it to Pending Appreciations on iPhone.
    /// Recipient is always nil — the user adds who to thank later on iPhone.
    func sendAppreciation(message: String, recipient: String?) async -> SendOutcome {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed("Speak a short note first.") }

        let clipped = String(trimmed.prefix(WatchRelay.watchMessageMaxLength))
        let draft = WatchRelay.CreateRequest(message: clipped, recipient: nil)

        guard isSignedIn else {
            return .failed("Sign in on iPhone to save thanks.")
        }

        let session = WCSession.default
        if session.isReachable {
            sendingIds.insert(draft.id)
            defer { sendingIds.remove(draft.id) }
            do {
                let reply = try await sendCreateMessage(draft)
                if reply.ok {
                    WatchDraftQueue.remove(draft.id)
                    return .sent
                }
                return .failed(reply.errorMessage ?? "Couldn't save. Try again.")
            } catch {
                WatchDraftQueue.enqueue(draft)
                transferCreateUserInfo(draft)
                return .queued("iPhone is busy — we'll save when it's nearby.")
            }
        } else {
            WatchDraftQueue.enqueue(draft)
            transferCreateUserInfo(draft)
            return .queued("Waiting for iPhone — open OpenThanks there if this stays pending.")
        }
    }

    /// Sends recorded voice to iPhone for transcription + Pending save.
    func sendVoiceAppreciation(fileURL: URL) async -> SendOutcome {
        guard isSignedIn else {
            return .failed("Sign in on iPhone to save thanks.")
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .failed("Recording missing — try again.")
        }

        let draftId = UUID()
        let session = WCSession.default
        guard session.activationState == .activated else {
            return .failed("Watch isn’t connected yet — open OpenThanks on iPhone.")
        }

        sendingIds.insert(draftId)
        defer { sendingIds.remove(draftId) }

        let waitTask = Task { await waitForCreateResult(draftId: draftId, timeoutSeconds: 75) }
        session.transferFile(
            fileURL,
            metadata: [
                WatchRelay.actionKey: WatchRelay.Action.createFromVoice.rawValue,
                WatchRelay.voiceDraftIdKey: draftId.uuidString,
            ]
        )

        if let reply = await waitTask.value {
            if reply.ok {
                WatchDraftQueue.remove(draftId)
                return .sent
            }
            return .failed(reply.errorMessage ?? "Couldn't save. Try again.")
        }

        // File is queued to the phone — result may arrive later via application context.
        return .queued("Sending to iPhone — keep OpenThanks open nearby.")
    }

    enum SendOutcome: Equatable {
        case sent
        case queued(String)
        case failed(String)
    }

    private var createResultWaiters: [UUID: CheckedContinuation<WatchRelay.CreateReply?, Never>] = [:]

    private func waitForCreateResult(draftId: UUID, timeoutSeconds: Double) async -> WatchRelay.CreateReply? {
        await withCheckedContinuation { (cont: CheckedContinuation<WatchRelay.CreateReply?, Never>) in
            createResultWaiters[draftId] = cont
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if let pending = createResultWaiters.removeValue(forKey: draftId) {
                    pending.resume(returning: nil)
                }
            }
        }
    }

    private func fulfillCreateResult(_ reply: WatchRelay.CreateReply) {
        if let waiter = createResultWaiters.removeValue(forKey: reply.draftId) {
            waiter.resume(returning: reply)
        }
        if reply.ok {
            WatchDraftQueue.remove(reply.draftId)
        }
    }

    func flushQueueIfPossible() async {
        guard isSignedIn, WCSession.default.isReachable else { return }
        for draft in WatchDraftQueue.all() {
            sendingIds.insert(draft.id)
            defer { sendingIds.remove(draft.id) }
            do {
                let reply = try await sendCreateMessage(draft)
                if reply.ok {
                    WatchDraftQueue.remove(draft.id)
                }
            } catch {
                break
            }
        }
    }

    private func sendCreateMessage(_ draft: WatchRelay.CreateRequest) async throws -> WatchRelay.CreateReply {
        guard let payload = WatchRelay.encode(draft) else {
            throw URLError(.cannotParseResponse)
        }
        let message: [String: Any] = [
            WatchRelay.actionKey: WatchRelay.Action.createAppreciation.rawValue,
            WatchRelay.payloadKey: payload,
        ]
        let reply = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[String: Any], Error>) in
            WCSession.default.sendMessage(message, replyHandler: { cont.resume(returning: $0) }, errorHandler: { cont.resume(throwing: $0) })
        }
        if let decoded = WatchRelay.decode(WatchRelay.CreateReply.self, fromAny: reply[WatchRelay.payloadKey]) {
            return decoded
        }
        if reply["ok"] as? Bool == true {
            return .success(draftId: draft.id, gratitudeId: UUID())
        }
        let code = reply["errorCode"] as? String ?? "unknown"
        let msg = reply["errorMessage"] as? String ?? "Couldn't save. Try again."
        return .failure(draftId: draft.id, code: code, message: msg)
    }

    private func transferCreateUserInfo(_ draft: WatchRelay.CreateRequest) {
        guard let payload = WatchRelay.encode(draft) else { return }
        WCSession.default.transferUserInfo([
            WatchRelay.actionKey: WatchRelay.Action.createAppreciation.rawValue,
            WatchRelay.payloadKey: payload,
        ])
    }

    private func ingestApplicationContext(_ context: [String: Any]) {
        if let auth = WatchRelay.decode(WatchRelay.AuthContext.self, fromAny: context[WatchRelay.authContextKey]) {
            self.auth = auth
        }
        if let result = WatchRelay.decode(WatchRelay.CreateReply.self, fromAny: context[WatchRelay.createResultKey]) {
            fulfillCreateResult(result)
        }
    }
}

extension WatchPhoneSession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            isActivated = activationState == .activated
            isReachable = session.isReachable
            if let error {
                lastError = error.localizedDescription
            }
            ingestApplicationContext(session.receivedApplicationContext)
            await flushQueueIfPossible()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isReachable = session.isReachable
            await flushQueueIfPossible()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor in
            ingestApplicationContext(applicationContext)
            await flushQueueIfPossible()
        }
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
