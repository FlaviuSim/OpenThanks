import CryptoKit
import Foundation
import Supabase

/// Stable idempotency key for create retries (same payload → same key).
private func idempotencyKey(from seed: String) -> String {
    let digest = SHA256.hash(data: Data(seed.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// All PostgREST access. Column and relationship names are taken verbatim
/// from the live schema (FK constraints: gratitudes_author_id_fkey,
/// gratitudes_recipient_id_fkey), so embeds resolve unambiguously.
enum GratitudeService {

    private static let feedSelect = """
    *,
    author:profiles!gratitudes_author_id_fkey(*),
    recipient:profiles!gratitudes_recipient_id_fkey(*),
    hearts(count)
    """

    /// Feed select plus parent appreciation for ripple / pay-it-forward chains.
    /// Use column embed `inspired_by_gratitude_id(...)` — PostgREST often fails to
    /// resolve self-FK constraint hints (`gratitudes!…_fkey`) with PGRST200.
    private static let rippleSelect = """
    *,
    author:profiles!gratitudes_author_id_fkey(*),
    recipient:profiles!gratitudes_recipient_id_fkey(*),
    hearts(count),
    inspiredByParent:inspired_by_gratitude_id(
        *,
        author:profiles!gratitudes_author_id_fkey(*),
        recipient:profiles!gratitudes_recipient_id_fkey(*)
    )
    """

    // MARK: Feeds

    /// World feed: public, accepted appreciations, newest accepted first.
    static func worldFeed(limit: Int = 30, before: Date? = nil) async throws -> [Gratitude] {
        var query = supabase.from("gratitudes")
            .select(feedSelect)
            .eq("visibility", value: "public")
            .eq("status", value: "accepted")
        if let before {
            query = query.lt("accepted_at", value: before.ISO8601Format())
        }
        return try await query
            .order("accepted_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    /// Personal feed: accepted appreciations you sent or received.
    static func personalFeed(userId: UUID, limit: Int = 30) async throws -> [Gratitude] {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .or("author_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString)")
            .eq("status", value: "accepted")
            .order("accepted_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    static func pending(authorId: UUID) async throws -> [Gratitude] {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("author_id", value: authorId)
            .eq("status", value: "pending")
            .order("created_at", ascending: false)
            .execute().value
    }

    /// Lightweight count for pending banners — no embeds.
    static func pendingCount(authorId: UUID) async throws -> Int {
        try await supabase.from("gratitudes")
            .select("id", head: true, count: .exact)
            .eq("author_id", value: authorId)
            .eq("status", value: "pending")
            .execute().count ?? 0
    }

    /// Pending appreciations the signed-in user still needs to accept
    /// (matched by recipient id, email, or phone — not ones they authored).
    static func pendingToAccept(
        userId: UUID,
        email: String?,
        phone: String?
    ) async throws -> [Gratitude] {
        var clauses = ["recipient_id.eq.\(userId.uuidString)"]
        if let email, !email.isEmpty {
            clauses.append("recipient_email.eq.\(email.lowercased())")
        }
        if let phone, !phone.isEmpty {
            clauses.append("recipient_phone.eq.\(phone)")
        }

        let rows: [Gratitude] = try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("status", value: "pending")
            .neq("author_id", value: userId)
            .or(clauses.joined(separator: ","))
            .order("created_at", ascending: false)
            .execute().value

        // De-dupe if multiple clauses match the same row.
        var seen = Set<UUID>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// Count of pending appreciations waiting for this user (widget snapshot).
    static func pendingToAcceptCount(
        userId: UUID,
        email: String? = nil,
        phone: String? = nil
    ) async throws -> Int {
        try await pendingToAccept(userId: userId, email: email, phone: phone).count
    }

    /// How many appreciations this user authored since the start of the calendar month.
    static func sentThisMonth(authorId: UUID) async throws -> Int {
        let start = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date())
        ) ?? Date()
        return try await supabase.from("gratitudes")
            .select("id", head: true, count: .exact)
            .eq("author_id", value: authorId)
            .gte("created_at", value: start.ISO8601Format())
            .execute().count ?? 0
    }

    /// Lightweight sent rows for Stats streaks / competition eligibility.
    static func sentActivity(
        authorId: UUID,
        since: Date,
        limit: Int = 500
    ) async throws -> [SentActivity] {
        try await supabase.from("gratitudes")
            .select("id, created_at, source, status, recipient_id, author_id")
            .eq("author_id", value: authorId)
            .gte("created_at", value: since.ISO8601Format())
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Accepted appreciations sent by a user, restricted to what `viewerId`
    /// may see: public posts, plus private ones the viewer is party to.
    static func sentBy(userId: UUID, viewerId: UUID?, limit: Int = 50) async throws -> [Gratitude] {
        let all: [Gratitude] = try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("author_id", value: userId)
            .eq("status", value: "accepted")
            .order("accepted_at", ascending: false)
            .limit(limit)
            .execute().value
        return all.filter { $0.isVisible(to: viewerId) }
    }

    /// Accepted appreciations received by a user, same visibility rules.
    static func receivedBy(userId: UUID, viewerId: UUID?, limit: Int = 50) async throws -> [Gratitude] {
        let all: [Gratitude] = try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("recipient_id", value: userId)
            .eq("status", value: "accepted")
            .order("accepted_at", ascending: false)
            .limit(limit)
            .execute().value
        return all.filter { $0.isVisible(to: viewerId) }
    }

    /// Single post (for notification taps).
    static func gratitude(id: UUID) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .select(rippleSelect)
            .eq("id", value: id)
            .single()
            .execute().value
    }

    /// Public post by SEO slug (`/for/{slug}`).
    static func gratitude(slug: String) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("slug", value: slug)
            .single()
            .execute().value
    }

    /// Pending appreciation opened via Universal Link claim token.
    static func gratitude(claimToken: UUID) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("claim_token", value: claimToken)
            .single()
            .execute().value
    }

    /// Associates the signed-in user as recipient when they open a claim link
    /// (or first see a pending appreciation matched by email/phone).
    /// Notifies them with `gratitude_pending` from the author (deduped).
    static func assignClaimRecipient(
        gratitudeId: UUID,
        claimToken: UUID,
        recipientId: UUID,
        authorId: UUID
    ) async throws {
        try await supabase.from("gratitudes")
            .update(["recipient_id": recipientId.uuidString])
            .eq("id", value: gratitudeId)
            .eq("claim_token", value: claimToken)
            .execute()

        await insertNotification(
            userId: recipientId,
            type: "gratitude_pending",
            gratitudeId: gratitudeId,
            fromUserId: authorId
        )
    }

    /// When a pending appreciation shows up for the signed-in user (email/phone
    /// match or already linked), attach `recipient_id` if needed and ensure the
    /// in-app `gratitude_pending` notification exists — so Notifications is not
    /// empty until they accept or decline.
    static func ensurePendingRecipientLinked(_ gratitude: Gratitude, userId: UUID) async {
        guard gratitude.status == .pending || gratitude.status == nil else { return }
        guard gratitude.authorId != userId else { return }

        if gratitude.recipientId != userId, let token = gratitude.claimToken {
            try? await assignClaimRecipient(
                gratitudeId: gratitude.id,
                claimToken: token,
                recipientId: userId,
                authorId: gratitude.authorId
            )
            return
        }

        if gratitude.recipientId == userId || gratitude.recipientId == nil {
            await insertNotification(
                userId: userId,
                type: "gratitude_pending",
                gratitudeId: gratitude.id,
                fromUserId: gratitude.authorId
            )
        }
    }

    /// Accept or decline a pending appreciation (mirrors web PATCH /api/gratitudes).
    static func respondToClaim(
        gratitudeId: UUID,
        recipientId: UUID,
        accept: Bool
    ) async throws -> Gratitude {
        struct ClaimUpdate: Encodable {
            let status: String
            let recipientId: String
            let acceptedAt: String?

            enum CodingKeys: String, CodingKey {
                case status
                case recipientId = "recipient_id"
                case acceptedAt = "accepted_at"
            }
        }

        let update = ClaimUpdate(
            status: accept ? "accepted" : "rejected",
            recipientId: recipientId.uuidString,
            acceptedAt: accept ? ISO8601DateFormatter().string(from: Date()) : nil
        )

        do {
            let updated: Gratitude = try await supabase.from("gratitudes")
                .update(update)
                .eq("id", value: gratitudeId)
                .eq("status", value: "pending")
                .select(feedSelect)
                .single()
                .execute().value

            if accept {
                await MainActor.run {
                    NotificationCenter.default.post(name: .gratitudeAccepted, object: updated)
                }
                // Don't hold the accept UI on notification insert.
                Task {
                    await insertNotification(
                        userId: updated.authorId,
                        type: "gratitude_received",
                        gratitudeId: updated.id,
                        fromUserId: recipientId
                    )
                }
            }

            return updated
        } catch {
            // Concurrent accept/decline already landed — return the current row.
            let current = try await gratitude(id: gratitudeId)
            if accept, current.status == .accepted {
                await MainActor.run {
                    NotificationCenter.default.post(name: .gratitudeAccepted, object: current)
                }
                return current
            }
            if !accept, current.status == .rejected {
                return current
            }
            throw error
        }
    }

    /// Hearts on posts this user sent or received — people they inspired.
    /// Excludes the profile owner hearting their own posts. Visibility of the
    /// underlying post is enforced for the viewer.
    static func inspirations(userId: UUID, viewerId: UUID?, limit: Int = 100) async throws -> [Inspiration] {
        let all: [Inspiration] = try await supabase.from("hearts")
            .select("""
            id, created_at,
            user:profiles!hearts_user_id_fkey(*),
            gratitude:gratitudes!hearts_gratitude_id_fkey!inner(
                *,
                author:profiles!gratitudes_author_id_fkey(*),
                recipient:profiles!gratitudes_recipient_id_fkey(*),
                hearts(count)
            )
            """)
            .or("author_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString)",
                referencedTable: "gratitudes")
            .eq("gratitude.status", value: "accepted")
            .neq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return all
            .filter { $0.gratitude?.isVisible(to: viewerId) ?? false }
            .reduce(into: [Inspiration]()) { unique, next in
                // One row per person (newest heart first).
                guard let personId = next.user?.id else {
                    unique.append(next)
                    return
                }
                if !unique.contains(where: { $0.user?.id == personId }) {
                    unique.append(next)
                }
            }
    }

    /// Accepted thanks inspired by an appreciation involving this profile
    /// (parent author or recipient), authored by someone else to someone else.
    /// Powers the Ripple Effect tab “Ripples” list — excludes posts where this
    /// profile is the giver or receiver of the child appreciation.
    static func ripples(userId: UUID, viewerId: UUID?, limit: Int = 100) async throws -> [Gratitude] {
        // 1) Parent posts this profile sent or received (ids only).
        struct IdRow: Decodable { let id: UUID }
        let parentRows: [IdRow] = try await supabase.from("gratitudes")
            .select("id")
            .or("author_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString)")
            .eq("status", value: "accepted")
            .limit(500)
            .execute().value
        let parentIds = parentRows.map(\.id)
        guard !parentIds.isEmpty else { return [] }

        // 2) Children that cite those parents — others thanking others.
        let all: [Gratitude] = try await supabase.from("gratitudes")
            .select(rippleSelect)
            .in("inspired_by_gratitude_id", values: parentIds.map { $0.uuidString.lowercased() })
            .neq("author_id", value: userId)
            .eq("status", value: "accepted")
            .order("created_at", ascending: false)
            .limit(limit * 2) // room after excluding self as recipient
            .execute().value

        return all
            .filter { child in
                guard child.authorId != userId else { return false }
                if child.recipientId == userId { return false }
                guard child.isVisible(to: viewerId) else { return false }
                guard let parent = child.inspiredByParent else { return false }
                return parent.isVisible(to: viewerId)
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Compose

    /// Creates a pending appreciation via the web create API so claim email
    /// resolution matches production (profiles.email → auth.users).
    static func create(_ new: NewGratitude) async throws -> Gratitude {
        var payload = new
        await resolveRecipientContact(&payload)

        guard let session = try? await supabase.auth.session else {
            throw URLError(.userAuthenticationRequired)
        }

        struct CreateBody: Encodable {
            let recipient_id: String?
            let recipient_email: String?
            let recipient_phone: String?
            let recipient_name: String?
            let message: String
            let media_url: String?
            let media_type: String?
            let visibility: String
            let source: String
        }

        struct CreateResponse: Decodable {
            let gratitude: Gratitude
            let emailSent: Bool?
        }

        var request = URLRequest(
            url: AppConfig.webAppURL.appending(path: "api/gratitudes")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        // Stable for this payload so retries after a timeout don't create duplicates.
        let idempotencySeed = [
            payload.authorId.uuidString,
            payload.message,
            payload.recipientId?.uuidString ?? "",
            payload.recipientEmail ?? "",
            payload.recipientPhone ?? "",
            payload.recipientName ?? "",
            payload.mediaUrl ?? "",
            payload.visibility,
        ].joined(separator: "|")
        request.setValue(idempotencyKey(from: idempotencySeed), forHTTPHeaderField: "X-Idempotency-Key")
        // Create returns after DB insert; claim email is sent asynchronously on the server.
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(
            CreateBody(
                recipient_id: payload.recipientId?.uuidString.lowercased(),
                recipient_email: payload.recipientEmail,
                recipient_phone: payload.recipientPhone,
                recipient_name: payload.recipientName,
                message: payload.message,
                media_url: payload.mediaUrl,
                media_type: payload.mediaType,
                visibility: payload.visibility,
                source: payload.source
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            struct APIError: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error
            throw NSError(
                domain: "OpenThanks",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: message ?? "Couldn't create the appreciation."
                ]
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var created = try decoder.decode(CreateResponse.self, from: data).gratitude

        // Web create API may not yet forward inspired_by — attach via direct update.
        if let parentId = payload.inspiredByGratitudeId {
            struct InspiredByUpdate: Encodable {
                let inspired_by_gratitude_id: String
            }
            _ = try? await supabase.from("gratitudes")
                .update(InspiredByUpdate(inspired_by_gratitude_id: parentId.uuidString.lowercased()))
                .eq("id", value: created.id)
                .eq("author_id", value: payload.authorId)
                .execute()
            created.inspiredByGratitudeId = parentId
        }

        // Re-fetch with feed embeds (author/recipient) for the success UI.
        if let hydrated: Gratitude = try? await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("id", value: created.id)
            .single()
            .execute()
            .value {
            return hydrated
        }
        return created
    }

    /// Contact fields for a member — used when thanking from their profile.
    struct ProfileContact: Decodable {
        let id: UUID
        let email: String?
        let phone: String?
        let fullName: String?

        enum CodingKeys: String, CodingKey {
            case id, email, phone
            case fullName = "full_name"
        }
    }

    static func profileContact(id: UUID) async throws -> ProfileContact {
        try await supabase.from("profiles")
            .select("id, email, phone, full_name")
            .eq("id", value: id)
            .single()
            .execute().value
    }

    /// Fills recipient_id / email / phone / name from profiles when thanking
    /// a member (e.g. from their profile) or when only an email/phone was typed.
    private static func resolveRecipientContact(_ payload: inout NewGratitude) async {
        if let recipientId = payload.recipientId {
            if let row = try? await profileContact(id: recipientId) {
                if isBlank(payload.recipientEmail),
                   let email = row.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !email.isEmpty {
                    payload.recipientEmail = AuthService.normalizedEmail(email)
                }
                if isBlank(payload.recipientPhone),
                   let phone = row.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !phone.isEmpty {
                    payload.recipientPhone = phone
                }
                if isBlank(payload.recipientName),
                   let name = row.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !name.isEmpty {
                    payload.recipientName = name
                }
            }
        }

        if payload.recipientId == nil {
            struct IdRow: Decodable { let id: UUID }
            if let email = payload.recipientEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !email.isEmpty,
               let row: IdRow = try? await supabase.from("profiles")
                .select("id")
                .eq("email", value: email)
                .single()
                .execute().value {
                payload.recipientId = row.id
            } else if let phone = payload.recipientPhone?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !phone.isEmpty,
                      let row: IdRow = try? await supabase.from("profiles")
                .select("id")
                .eq("phone", value: phone)
                .single()
                .execute().value {
                payload.recipientId = row.id
            }
        }
    }

    private static func isBlank(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    /// Update a pending appreciation you authored.
    static func update(id: UUID, update: GratitudeUpdate) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .update(update)
            .eq("id", value: id)
            .select(feedSelect)
            .single()
            .execute().value
    }

    /// Delete an appreciation you authored (typically still pending).
    static func delete(id: UUID) async throws {
        try await supabase.from("gratitudes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Uploads a profile photo and returns its public URL.
    static func uploadAvatar(data: Data, contentType: String, userId: UUID) async throws -> URL {
        try await uploadToBucket(AppConfig.avatarBucket, data: data, contentType: contentType, userId: userId)
    }

    /// Uploads a post photo/video and returns its public URL.
    static func uploadMedia(data: Data, contentType: String, userId: UUID) async throws -> URL {
        try await uploadToBucket(AppConfig.mediaBucket, data: data, contentType: contentType, userId: userId)
    }

    private static func uploadToBucket(
        _ bucket: String,
        data: Data,
        contentType: String,
        userId: UUID
    ) async throws -> URL {
        let ext = Self.fileExtension(for: contentType)
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
        try await supabase.storage
            .from(bucket)
            .upload(path, data: data, options: .init(contentType: contentType, upsert: true))
        return try supabase.storage.from(bucket).getPublicURL(path: path)
    }

    private static func fileExtension(for contentType: String) -> String {
        let lower = contentType.lowercased()
        if lower.contains("png") { return "png" }
        if lower.contains("webp") { return "webp" }
        if lower.contains("mp4") { return "mp4" }
        if lower.contains("webm") { return "webm" }
        if lower.contains("quicktime") || lower.contains("mov") { return "mov" }
        if lower.contains("jpeg") || lower.contains("jpg") { return "jpg" }
        return "bin"
    }

    // MARK: Hearts

    /// Returns the set of gratitude IDs the user has hearted, among `ids`.
    static func myHearts(userId: UUID, among ids: [UUID]) async throws -> Set<UUID> {
        guard !ids.isEmpty else { return [] }
        struct Row: Decodable { let gratitude_id: UUID }
        let rows: [Row] = try await supabase.from("hearts")
            .select("gratitude_id")
            .eq("user_id", value: userId)
            .in("gratitude_id", values: ids.map(\.uuidString))
            .execute().value
        return Set(rows.map(\.gratitude_id))
    }

    /// People who hearted an appreciation, most recent first.
    /// `hearts.user_id` points at auth.users, so profiles are fetched in a
    /// second query (same approach as the web `/api/hearts` endpoint).
    static func hearters(for gratitudeId: UUID, limit: Int = 50) async throws -> (count: Int, hearters: [Profile]) {
        struct HeartRow: Decodable {
            let userId: UUID
            enum CodingKeys: String, CodingKey { case userId = "user_id" }
        }

        let rows: [HeartRow] = try await supabase.from("hearts")
            .select("user_id, created_at")
            .eq("gratitude_id", value: gratitudeId)
            .order("created_at", ascending: false)
            .execute().value

        let count = rows.count
        guard count > 0 else { return (0, []) }

        let previewIds = Array(rows.prefix(limit).map(\.userId))
        let profiles: [Profile] = try await supabase.from("profiles")
            .select("id, username, full_name, avatar_url, headline")
            .in("id", values: previewIds.map(\.uuidString))
            .execute().value

        let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let ordered = previewIds.compactMap { byId[$0] }
        return (count, ordered)
    }

    static func heart(gratitudeId: UUID, userId: UUID, authorId: UUID) async throws {
        try await supabase.from("hearts")
            .insert(["gratitude_id": gratitudeId.uuidString,
                     "user_id": userId.uuidString])
            .execute()

        // Notify the author (skip self-hearts).
        if authorId != userId {
            await insertNotification(
                userId: authorId,
                type: "heart_received",
                gratitudeId: gratitudeId,
                fromUserId: userId
            )
        }
    }

    static func unheart(gratitudeId: UUID, userId: UUID) async throws {
        try await supabase.from("hearts")
            .delete()
            .eq("gratitude_id", value: gratitudeId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: Notifications

    /// Best-effort insert — never fails the calling action.
    /// Dedupes `gratitude_pending` (same recipient + post) and `heart_received`
    /// (same hearter + post) so repeat link/heart actions don't spam the inbox.
    private static func insertNotification(
        userId: UUID,
        type: String,
        gratitudeId: UUID,
        fromUserId: UUID
    ) async {
        if type == "gratitude_pending" || type == "heart_received" {
            struct IdRow: Decodable { let id: UUID }
            var query = supabase.from("notifications")
                .select("id")
                .eq("user_id", value: userId)
                .eq("gratitude_id", value: gratitudeId)
                .eq("type", value: type)
            if type == "heart_received" {
                query = query.eq("from_user_id", value: fromUserId)
            }
            let existing: [IdRow] = (try? await query
                .limit(1)
                .execute().value) ?? []
            if !existing.isEmpty { return }
        }

        _ = try? await supabase.from("notifications").insert([
            "user_id": userId.uuidString,
            "type": type,
            "gratitude_id": gratitudeId.uuidString,
            "from_user_id": fromUserId.uuidString,
        ]).execute()
    }

    static func notifications(userId: UUID, limit: Int = 50) async throws -> [AppNotification] {
        await expireStaleFridayNotifications(userId: userId)
        let notes: [AppNotification] = try await supabase.from("notifications")
            .select("*, from_user:profiles!notifications_from_user_id_fkey(*)")
            .eq("user_id", value: userId)
            .or(Self.activeNotificationsOrFilter)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return notes
    }

    /// Badge count only — avoids loading notification rows + profile embeds.
    static func unreadNotificationCount(userId: UUID) async throws -> Int {
        try await supabase.from("notifications")
            .select("id", head: true, count: .exact)
            .eq("user_id", value: userId)
            .eq("read", value: false)
            .or(Self.activeNotificationsOrFilter)
            .execute().count ?? 0
    }

    /// Weekly Friday prompts older than this leave the inbox.
    static let fridayNotificationMaxAgeDays = 21

    /// PostgREST `or`: keep non-Friday rows, or Friday rows within the retention window.
    private static var activeNotificationsOrFilter: String {
        // Quote the timestamp — unquoted ISO8601 colons break PostgREST parsing.
        "type.neq.gratitude_friday,created_at.gte.\"\(fridayNotificationCutoffISO8601)\""
    }

    private static var fridayNotificationCutoffISO8601: String {
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -fridayNotificationMaxAgeDays,
            to: Date()
        ) ?? Date().addingTimeInterval(-TimeInterval(fridayNotificationMaxAgeDays * 86_400))
        return ISO8601DateFormatter().string(from: cutoff)
    }

    /// Deletes this user's Friday prompts older than three weeks (don't wait for cron).
    private static func expireStaleFridayNotifications(userId: UUID) async {
        _ = try? await supabase.from("notifications")
            .delete()
            .eq("user_id", value: userId)
            .eq("type", value: "gratitude_friday")
            .lt("created_at", value: fridayNotificationCutoffISO8601)
            .execute()
    }

    static func markRead(id: UUID) async throws {
        try await supabase.from("notifications")
            .update(["read": true])
            .eq("id", value: id)
            .execute()
    }

    static func markAllRead(userId: UUID) async throws {
        try await supabase.from("notifications")
            .update(["read": true])
            .eq("user_id", value: userId)
            .eq("read", value: false)
            .execute()
    }

    // MARK: Stats

    static func stats(userId: UUID) async throws -> ProfileStats {
        async let sent = supabase.from("gratitudes")
            .select("id", head: true, count: .exact)
            .eq("author_id", value: userId)
            .eq("status", value: "accepted")
            .execute().count
        async let received = supabase.from("gratitudes")
            .select("id", head: true, count: .exact)
            .eq("recipient_id", value: userId)
            .eq("status", value: "accepted")
            .execute().count
        // Distinct people who hearted an accepted post this user sent or received,
        // excluding the user hearting their own posts.
        struct HeartRow: Decodable { let user_id: UUID }
        async let inspiredRows: [HeartRow] = supabase.from("hearts")
            .select("user_id, gratitudes!inner(author_id, recipient_id, status)")
            .or("author_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString)",
                referencedTable: "gratitudes")
            .eq("gratitudes.status", value: "accepted")
            .neq("user_id", value: userId)
            .execute().value

        let (sentCount, receivedCount, rows) = try await (sent, received, inspiredRows)

        // Ripples: accepted children inspired by a post this user sent or received.
        let rippleRows = (try? await ripples(userId: userId, viewerId: userId, limit: 200)) ?? []

        return ProfileStats(
            sent: sentCount ?? 0,
            received: receivedCount ?? 0,
            inspired: Set(rows.map(\.user_id)).count,
            ripplesPassedOn: rippleRows.count
        )
    }

    // MARK: Profile

    static func profile(id: UUID) async throws -> Profile {
        try await supabase.from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute().value
    }

    static func profile(username: String) async throws -> Profile {
        try await supabase.from("profiles")
            .select()
            .eq("username", value: username.lowercased())
            .single()
            .execute().value
    }

    /// Lookup by email (calendar attendee → OpenThanks member chip).
    static func profile(email: String) async throws -> Profile? {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        let rows: [Profile] = try await supabase.from("profiles")
            .select()
            .eq("email", value: normalized)
            .limit(1)
            .execute().value
        return rows.first
    }

    /// People search by name or username (same filters as the web home search).
    static func searchProfiles(query: String, limit: Int = 10) async throws -> [Profile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        // Keep the PostgREST `or` filter valid and avoid wildcard injection.
        let safe = trimmed
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard safe.count >= 2 else { return [] }

        let pattern = "%\(safe)%"
        return try await supabase.from("profiles")
            .select()
            .or("full_name.ilike.\"\(pattern)\",username.ilike.\"\(pattern)\"")
            .order("full_name", ascending: true)
            .limit(limit)
            .execute().value
    }

    /// Profile update. Pass `clearOptionalFields: true` from Edit Profile so
    /// clearing headline/nonprofit writes SQL NULL. Required onboarding patches
    /// name, username, avatar, and optional headline.
    struct ProfileUpdate: Encodable {
        var fullName: String?
        var username: String
        var avatarUrl: String?
        var headline: String?
        var favoriteNonprofitEin: String?
        var favoriteNonprofitName: String?
        var favoriteNonprofitWebsite: String?
        var favoriteNonprofitHeadline: String?
        var clearOptionalFields = false

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case username
            case avatarUrl = "avatar_url"
            case headline
            case favoriteNonprofitEin = "favorite_nonprofit_ein"
            case favoriteNonprofitName = "favorite_nonprofit_name"
            case favoriteNonprofitWebsite = "favorite_nonprofit_website"
            case favoriteNonprofitHeadline = "favorite_nonprofit_headline"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(fullName, forKey: .fullName)
            try c.encode(username, forKey: .username)
            try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
            if clearOptionalFields {
                try c.encode(headline, forKey: .headline)
                try c.encode(favoriteNonprofitEin, forKey: .favoriteNonprofitEin)
                try c.encode(favoriteNonprofitName, forKey: .favoriteNonprofitName)
                try c.encode(favoriteNonprofitWebsite, forKey: .favoriteNonprofitWebsite)
                try c.encode(favoriteNonprofitHeadline, forKey: .favoriteNonprofitHeadline)
            } else {
                try c.encodeIfPresent(headline, forKey: .headline)
                try c.encodeIfPresent(favoriteNonprofitEin, forKey: .favoriteNonprofitEin)
                try c.encodeIfPresent(favoriteNonprofitName, forKey: .favoriteNonprofitName)
                try c.encodeIfPresent(favoriteNonprofitWebsite, forKey: .favoriteNonprofitWebsite)
                try c.encodeIfPresent(favoriteNonprofitHeadline, forKey: .favoriteNonprofitHeadline)
            }
        }
    }

    static func updateProfile(userId: UUID, update: ProfileUpdate) async throws -> Profile {
        try await supabase.from("profiles")
            .update(update)
            .eq("id", value: userId)
            .select()
            .single()
            .execute().value
    }

    // MARK: Email reminders

    /// Sends the OpenThanks claim email to the pending recipient
    /// (`POST /api/gratitudes/resend-email` on openthanks.com).
    static func sendEmailReminder(gratitudeId: UUID) async throws {
        guard let session = try? await supabase.auth.session else {
            throw URLError(.userAuthenticationRequired)
        }

        var request = URLRequest(
            url: AppConfig.webAppURL.appending(path: "api/gratitudes/resend-email")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["gratitudeId": gratitudeId.uuidString])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            struct APIError: Decodable { let error: String? }
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error
            throw NSError(
                domain: "OpenThanks",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message ?? "Couldn't send the email reminder."]
            )
        }
    }

    // MARK: Nonprofits

    /// Nonprofit lookup via the web app's public search endpoint
    /// (ProPublica Nonprofit Explorer under the hood).
    static func searchNonprofits(query: String) async throws -> [NonprofitOrg] {
        var components = URLComponents(url: AppConfig.webAppURL.appending(path: "api/nonprofits/search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        struct Response: Decodable { let organizations: [NonprofitOrg] }
        return try JSONDecoder().decode(Response.self, from: data).organizations
    }
}
