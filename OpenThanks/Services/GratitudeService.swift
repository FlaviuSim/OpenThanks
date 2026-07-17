import Foundation
import Supabase

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

    // MARK: Feeds

    /// World feed: public, accepted appreciations, newest first.
    static func worldFeed(limit: Int = 30, before: Date? = nil) async throws -> [Gratitude] {
        var query = supabase.from("gratitudes")
            .select(feedSelect)
            .eq("visibility", value: "public")
            .eq("status", value: "accepted")
        if let before {
            query = query.lt("created_at", value: before.ISO8601Format())
        }
        return try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    /// Personal feed: accepted appreciations you sent or received.
    static func personalFeed(userId: UUID, limit: Int = 30) async throws -> [Gratitude] {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .or("author_id.eq.\(userId.uuidString),recipient_id.eq.\(userId.uuidString)")
            .eq("status", value: "accepted")
            .order("created_at", ascending: false)
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

    /// Accepted appreciations sent by a user, restricted to what `viewerId`
    /// may see: public posts, plus private ones the viewer is party to.
    static func sentBy(userId: UUID, viewerId: UUID?, limit: Int = 50) async throws -> [Gratitude] {
        let all: [Gratitude] = try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("author_id", value: userId)
            .eq("status", value: "accepted")
            .order("created_at", ascending: false)
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
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
        return all.filter { $0.isVisible(to: viewerId) }
    }

    /// Single post (for notification taps).
    static func gratitude(id: UUID) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .select(feedSelect)
            .eq("id", value: id)
            .single()
            .execute().value
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

    // MARK: Compose

    static func create(_ new: NewGratitude) async throws -> Gratitude {
        try await supabase.from("gratitudes")
            .insert(new)
            .select(feedSelect)
            .single()
            .execute().value
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
        let ext = contentType.contains("png") ? "png" : "jpg"
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).\(ext)"
        try await supabase.storage
            .from(bucket)
            .upload(path, data: data, options: .init(contentType: contentType, upsert: true))
        return try supabase.storage.from(bucket).getPublicURL(path: path)
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

    static func heart(gratitudeId: UUID, userId: UUID) async throws {
        try await supabase.from("hearts")
            .insert(["gratitude_id": gratitudeId.uuidString,
                     "user_id": userId.uuidString])
            .execute()
    }

    static func unheart(gratitudeId: UUID, userId: UUID) async throws {
        try await supabase.from("hearts")
            .delete()
            .eq("gratitude_id", value: gratitudeId)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: Notifications

    static func notifications(userId: UUID, limit: Int = 50) async throws -> [AppNotification] {
        try await supabase.from("notifications")
            .select("*, from_user:profiles!notifications_from_user_id_fkey(*)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute().value
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
        return ProfileStats(sent: sentCount ?? 0,
                            received: receivedCount ?? 0,
                            inspired: Set(rows.map(\.user_id)).count)
    }

    // MARK: Profile

    static func profile(id: UUID) async throws -> Profile {
        try await supabase.from("profiles")
            .select()
            .eq("id", value: id)
            .single()
            .execute().value
    }

    /// Profile update. Pass `clearOptionalFields: true` from Edit Profile so
    /// clearing headline/nonprofit writes SQL NULL. Required onboarding only
    /// patches name, username, and avatar.
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
