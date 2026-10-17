import Foundation

/// Best-effort copy of the local compose draft on the signed-in account.
///
/// Signed-out drafts stay on the device. Failures are ignored so a missing
/// network never changes the local reminder.
enum ComposeDraftSync {
    private static let lock = NSLock()
    private static var chain: Task<Void, Never> = Task {}

    struct RemoteDraft: Decodable, Equatable {
        let id: UUID
        let recipient: String
        let message: String
        let pushChannel: String

        enum CodingKeys: String, CodingKey {
            case id, recipient, message
            case pushChannel = "push_channel"
        }

        /// A push is already planned or delivered for this draft.
        var suppressesAnotherLocalPush: Bool {
            pushChannel == "local" || pushChannel == "remote"
        }
    }

    /// Uploads the current local draft, or deletes the account row when the
    /// device draft is gone. Calls are ordered so a later clear wins.
    static func scheduleSync() {
        enqueue {
            guard await hasSession else { return }
            if let draft = ComposeDraftStore.load() {
                await upsert(draft)
            } else {
                await delete()
            }
        }
    }

    /// The push was opened, so the later email should not be sent.
    static func markPushResponded() {
        enqueue {
            guard await hasSession else { return }
            _ = try? await supabase.rpc("respond_compose_draft").execute()
        }
    }

    /// The signed-in account's draft, if any. Nil when signed out or offline.
    static func fetch() async -> RemoteDraft? {
        guard await hasSession else { return nil }
        let rows: [RemoteDraft] = (try? await supabase
            .from("compose_drafts")
            .select("id, recipient, message, push_channel")
            .limit(1)
            .execute()
            .value) ?? []
        return rows.first
    }

    // MARK: - Private

    private static func enqueue(_ work: @escaping @Sendable () async -> Void) {
        lock.lock()
        let previous = chain
        chain = Task {
            await previous.value
            await work()
        }
        lock.unlock()
    }

    private static var hasSession: Bool {
        get async { (try? await supabase.auth.session) != nil }
    }

    private struct UpsertParams: Encodable {
        let pId: String
        let pRecipient: String
        let pMessage: String
        let pPushScheduled: Bool
        let pOrigin: String

        enum CodingKeys: String, CodingKey {
            case pId = "p_id"
            case pRecipient = "p_recipient"
            case pMessage = "p_message"
            case pPushScheduled = "p_push_scheduled"
            case pOrigin = "p_origin"
        }
    }

    private static func upsert(_ draft: ComposeDraftStore.Draft) async {
        let params = UpsertParams(
            pId: draft.id.uuidString.lowercased(),
            pRecipient: draft.recipient,
            pMessage: draft.message,
            pPushScheduled: draft.reminderScheduled,
            pOrigin: "ios"
        )
        _ = try? await supabase.rpc("upsert_compose_draft", params: params).execute()
    }

    private static func delete() async {
        _ = try? await supabase.rpc("delete_compose_draft").execute()
    }
}
