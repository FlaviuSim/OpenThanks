import Foundation
import UserNotifications

/// Local notification category so Watch (and iPhone) taps open compose / record.
enum WatchComposeNotification {
    static let categoryIdentifier = "openthanks.compose"
    static let recordActionIdentifier = "openthanks.compose.record"

    /// userInfo `type` values that should open Watch compose + auto-record.
    static let composeOpenTypeValues: Set<String> = [
        "gratitude_friday",
        "thank_reminder",
        "calendar_gratitude_nudge",
        "streak_live_activity_wake",
    ]

    static func registerCategories() {
        let record = UNNotificationAction(
            identifier: recordActionIdentifier,
            title: "Record a thanks",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [record],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func shouldOpenCompose(from response: UNNotificationResponse) -> Bool {
        let category = response.notification.request.content.categoryIdentifier
        let action = response.actionIdentifier
        if category == categoryIdentifier {
            return action == UNNotificationDefaultActionIdentifier
                || action == recordActionIdentifier
        }
        let info = response.notification.request.content.userInfo
        guard let type = info["type"] as? String else { return false }
        return composeOpenTypeValues.contains(type)
            && (action == UNNotificationDefaultActionIdentifier || action == recordActionIdentifier)
    }
}

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

    /// True when the Watch "To" field should trigger an email claim link (vs save-to-pending).
    static func looksLikeEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !local.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
            && !domain.contains("@")
    }

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

/// In-progress Watch compose note (survives interruption / app relaunch before Save/Send).
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
