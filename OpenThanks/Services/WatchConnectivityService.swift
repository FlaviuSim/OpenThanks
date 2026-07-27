import Foundation
import WatchConnectivity

/// iPhone side of Watch Connectivity: pushes auth context and creates appreciations.
@MainActor
final class WatchConnectivityService: NSObject {
    static let shared = WatchConnectivityService()

    private weak var auth: AuthService?
    private var activated = false

    func activate(auth: AuthService) {
        self.auth = auth
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil || !(session.delegate is WatchConnectivityService) {
            session.delegate = self
        }
        if session.activationState != .activated {
            session.activate()
        }
        activated = true
        pushAuthContext()
    }

    func pushAuthContext() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

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
            print("WatchConnectivity auth context failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Create

    private func handleCreate(_ request: WatchRelay.CreateRequest) async -> WatchRelay.CreateReply {
        guard let auth, let userId = auth.userId else {
            return .failure(
                draftId: request.id,
                code: "notSignedIn",
                message: "Sign in on iPhone to send thanks."
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
            Analytics.appreciationSubmitted(
                hasMedia: false,
                messageLength: clipped.count,
                hasRecipient: contact.email != nil || contact.phone != nil || !(contact.name ?? "").isEmpty,
                visibility: GratitudeVisibility.public.rawValue,
                source: "watch"
            )
            await WidgetSnapshotRefresher.refresh(
                displayName: auth.currentProfile?.displayName,
                userId: userId,
                email: auth.currentProfile?.email,
                phone: auth.currentProfile?.phone
            )
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
        guard session.activationState == .activated else { return }

        var context: [String: Any] = [WatchRelay.createResultKey: replyData]
        let authContext = WatchRelay.AuthContext(
            isSignedIn: auth?.userId != nil,
            displayName: auth?.currentProfile?.displayName,
            userId: auth?.userId?.uuidString
        )
        if let authData = WatchRelay.encode(authContext) {
            context[WatchRelay.authContextKey] = authData
        }
        do {
            try session.updateApplicationContext(context)
        } catch {
            // Best-effort; interactive replies already cover the happy path.
        }
    }

    private static func parseRecipient(_ raw: String?)
        -> (name: String?, email: String?, phone: String?) {
        guard let raw else { return (nil, nil, nil) }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return (nil, nil, nil) }
        if looksLikeEmail(value) {
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

    private static func looksLikeEmail(_ value: String) -> Bool {
        guard let at = value.firstIndex(of: "@") else { return false }
        let local = value[..<at]
        let domain = value[value.index(after: at)...]
        return !local.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !domain.contains("@")
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            pushAuthContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
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
