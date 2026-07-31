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
    /// Draft ids currently sending (interactive or flush).
    private(set) var sendingIds: Set<UUID> = []

    private var didActivate = false

    override init() {
        super.init()
        activate()
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

    /// Save to Pending Appreciations on iPhone (or email a claim link when `recipient` is an email).
    func sendAppreciation(message: String, recipient: String?) async -> SendOutcome {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed("Write a short note first.") }

        let clipped = String(trimmed.prefix(WatchRelay.watchMessageMaxLength))
        let to = recipient?.trimmingCharacters(in: .whitespacesAndNewlines)
        let willEmail = WatchRelay.looksLikeEmail(to ?? "")
        let draft = WatchRelay.CreateRequest(
            message: clipped,
            recipient: (to?.isEmpty == false) ? to : nil
        )

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
                    return .sent(emailed: willEmail)
                }
                let fallback = willEmail ? "Couldn't send. Try again." : "Couldn't save. Try again."
                return .failed(reply.errorMessage ?? fallback)
            } catch {
                WatchDraftQueue.enqueue(draft)
                transferCreateUserInfo(draft)
                let note = willEmail
                    ? "iPhone is busy — we'll send when it's nearby."
                    : "iPhone is busy — we'll save it when it's nearby."
                return .queued(note)
            }
        } else {
            WatchDraftQueue.enqueue(draft)
            transferCreateUserInfo(draft)
            return .queued("Waiting for iPhone — open OpenThanks there if this stays pending.")
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

    enum SendOutcome: Equatable {
        case sent(emailed: Bool)
        case queued(String)
        case failed(String)
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
        let willEmail = WatchRelay.looksLikeEmail(draft.recipient ?? "")
        let fallback = willEmail ? "Couldn't send. Try again." : "Couldn't save. Try again."
        let msg = reply["errorMessage"] as? String ?? fallback
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
        if let result = WatchRelay.decode(WatchRelay.CreateReply.self, fromAny: context[WatchRelay.createResultKey]),
           result.ok {
            WatchDraftQueue.remove(result.draftId)
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
