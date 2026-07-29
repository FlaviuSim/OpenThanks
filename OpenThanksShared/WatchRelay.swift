import Foundation

/// Shared Watch ↔ iPhone relay contract (Watch Connectivity).
enum WatchRelay {
    static let actionKey = "action"
    static let payloadKey = "payload"
    static let authContextKey = "authContext"
    static let createResultKey = "createResult"

    enum Action: String, Codable {
        case createAppreciation
        case ping
    }

    /// Pushed from iPhone via `updateApplicationContext`.
    struct AuthContext: Codable, Equatable {
        var isSignedIn: Bool
        var displayName: String?
        var userId: String?

        static let signedOut = AuthContext(isSignedIn: false, displayName: nil, userId: nil)
    }

    /// Draft the Watch wants the phone to create.
    struct CreateRequest: Codable, Equatable, Identifiable {
        var id: UUID
        var message: String
        var recipient: String?
        var createdAt: Date

        init(
            id: UUID = UUID(),
            message: String,
            recipient: String? = nil,
            createdAt: Date = .now
        ) {
            self.id = id
            self.message = message
            self.recipient = recipient
            self.createdAt = createdAt
        }
    }

    struct CreateReply: Codable, Equatable {
        var ok: Bool
        var draftId: UUID
        var gratitudeId: String?
        var errorCode: String?
        var errorMessage: String?

        static func success(draftId: UUID, gratitudeId: UUID) -> CreateReply {
            CreateReply(
                ok: true,
                draftId: draftId,
                gratitudeId: gratitudeId.uuidString,
                errorCode: nil,
                errorMessage: nil
            )
        }

        static func failure(draftId: UUID, code: String, message: String) -> CreateReply {
            CreateReply(
                ok: false,
                draftId: draftId,
                gratitudeId: nil,
                errorCode: code,
                errorMessage: message
            )
        }
    }

    /// Soft max for Watch readability; API still allows longer messages from phone.
    static let watchMessageMaxLength = 280

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    static func decode<T: Decodable>(_ type: T.Type, fromAny object: Any?) -> T? {
        if let data = object as? Data {
            return decode(type, from: data)
        }
        if let dict = object as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict) {
            return decode(type, from: data)
        }
        return nil
    }
}

/// In-progress Watch compose note (survives interruption / app relaunch before Send).
enum WatchComposeDraftStore {
    private static let key = "watchComposeDraft.v1"

    struct Draft: Codable, Equatable {
        var message: String
        var recipient: String
    }

    static func load() -> Draft? {
        guard let data = AppGroup.defaults.data(forKey: key),
              let draft = try? JSONDecoder().decode(Draft.self, from: data)
        else { return nil }
        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = draft.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty && recipient.isEmpty { return nil }
        return Draft(message: message, recipient: recipient)
    }

    static func save(message: String, recipient: String) {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRecipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedMessage.isEmpty && trimmedRecipient.isEmpty {
            clear()
            return
        }
        let draft = Draft(message: trimmedMessage, recipient: trimmedRecipient)
        guard let data = try? JSONEncoder().encode(draft) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }
}

/// Local queue of Watch drafts waiting for a reachable, signed-in iPhone.
enum WatchDraftQueue {
    private static let key = "watchDraftQueue.v1"

    static func all() -> [WatchRelay.CreateRequest] {
        guard let data = AppGroup.defaults.data(forKey: key),
              let items = try? JSONDecoder().decode([WatchRelay.CreateRequest].self, from: data)
        else { return [] }
        return items.sorted { $0.createdAt < $1.createdAt }
    }

    static func enqueue(_ draft: WatchRelay.CreateRequest) {
        var items = all().filter { $0.id != draft.id }
        items.append(draft)
        save(items)
    }

    static func remove(_ id: UUID) {
        save(all().filter { $0.id != id })
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }

    private static func save(_ items: [WatchRelay.CreateRequest]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}
