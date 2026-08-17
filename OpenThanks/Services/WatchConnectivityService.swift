import Foundation
import WatchConnectivity

/// iPhone side of Watch Connectivity: pushes auth context and creates appreciations.
/// Safe with no Watch paired — activates once, then no-ops until a Watch is available.
@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private weak var auth: AuthService?
    private var didRequestActivation = false

    /// True after activation completes with a paired Watch that has our companion installed.
    private(set) var isWatchReady = false

    func activate(auth: AuthService) {
        self.auth = auth
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
            pushAuthContext()
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
        do {
            try session.updateApplicationContext([WatchRelay.authContextKey: data])
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

        let clipped = String(message.prefix(1_500))
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

    private func publishCreateResult(_ reply: WatchRelay.CreateReply) {
        guard WCSession.isSupported(),
              let replyData = WatchRelay.encode(reply) else { return }
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
