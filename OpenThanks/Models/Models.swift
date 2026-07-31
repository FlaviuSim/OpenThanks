import Foundation

// Models mirror the verified `public` schema of project dsftvyuzmhlqadhbubgw.

extension Notification.Name {
    /// Posted with a `Gratitude` object after the recipient accepts.
    static let gratitudeAccepted = Notification.Name("openthanks.gratitudeAccepted")
}

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var fullName: String?
    var headline: String?
    var avatarUrl: String?
    var email: String?
    var username: String
    var phone: String?
    var favoriteNonprofitEin: String?
    var favoriteNonprofitName: String?
    var favoriteNonprofitWebsite: String?
    var favoriteNonprofitHeadline: String?

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case headline
        case avatarUrl = "avatar_url"
        case email
        case username
        case phone
        case favoriteNonprofitEin = "favorite_nonprofit_ein"
        case favoriteNonprofitName = "favorite_nonprofit_name"
        case favoriteNonprofitWebsite = "favorite_nonprofit_website"
        case favoriteNonprofitHeadline = "favorite_nonprofit_headline"
    }

    var displayName: String { fullName ?? "@\(username)" }
    /// First name for compact “hearted by” summaries (matches the web UI).
    var firstName: String {
        if let fullName,
           let first = fullName.split(whereSeparator: \.isWhitespace).first,
           !first.isEmpty {
            return String(first)
        }
        return displayName
    }
    var avatarURL: URL? { AppConfig.mediaURL(from: avatarUrl) }
    var webProfileURL: URL { AppConfig.webAppURL.appending(path: username) }
    var isCompleteForApp: Bool {
        let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let handle = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !handle.isEmpty
    }
}

enum GratitudeStatus: String, Codable { case pending, accepted, rejected }
enum GratitudeVisibility: String, Codable { case `public`, `private` }

struct Gratitude: Codable, Identifiable, Hashable {
    let id: UUID
    let authorId: UUID
    let recipientId: UUID?
    var message: String
    var mediaUrl: String?
    var mediaType: String?
    let createdAt: Date?
    let acceptedAt: Date?
    var status: GratitudeStatus?
    var visibility: GratitudeVisibility?
    var recipientEmail: String?
    var recipientPhone: String?
    var recipientName: String?
    var slug: String?
    var claimToken: UUID?

    // Embedded relations (PostgREST resource embedding)
    var author: Profile?
    var recipient: Profile?
    var hearts: [CountHolder]?

    enum CodingKeys: String, CodingKey {
        case id
        case authorId = "author_id"
        case recipientId = "recipient_id"
        case message
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case createdAt = "created_at"
        case acceptedAt = "accepted_at"
        case status, visibility, slug
        case recipientEmail = "recipient_email"
        case recipientPhone = "recipient_phone"
        case recipientName = "recipient_name"
        case claimToken = "claim_token"
        case author, recipient, hearts
    }

    /// Prefer acceptance date for listing/display; fall back to sent date.
    var displayDate: Date? { acceptedAt ?? createdAt }

    /// Sort key for accepted lists (newest acceptance first).
    var acceptanceSortDate: Date { acceptedAt ?? createdAt ?? .distantPast }

    var heartCount: Int { hearts?.first?.count ?? 0 }
    var recipientDisplayName: String {
        recipient?.displayName ?? recipientName ?? recipientEmail ?? recipientPhone ?? "Someone"
    }
    var mediaURL: URL? { AppConfig.mediaURL(from: mediaUrl) }

    /// Public post page on openthanks.com (matches the web app's route:
    /// /for/{slug}, falling back to /gratitude/{id}).
    var webURL: URL {
        if let slug, !slug.isEmpty {
            return AppConfig.webAppURL.appending(path: "for/\(slug)")
        }
        return AppConfig.webAppURL.appending(path: "gratitude/\(id.uuidString.lowercased())")
    }

    /// Claim page the recipient opens to accept a pending appreciation.
    var claimURL: URL? {
        guard let claimToken else { return nil }
        return AppConfig.webAppURL.appending(path: "claim/\(claimToken.uuidString.lowercased())")
    }

    /// Whether `viewerId` is allowed to see this post: public posts are open,
    /// private ones only to their author and recipient.
    func isVisible(to viewerId: UUID?) -> Bool {
        if visibility != .private { return true }
        guard let viewerId else { return false }
        return authorId == viewerId || recipientId == viewerId
    }
}

struct CountHolder: Codable, Hashable { let count: Int }

struct NewGratitude: Encodable {
    let authorId: UUID
    let message: String
    var recipientEmail: String?
    var recipientPhone: String?
    var recipientName: String?
    var recipientId: UUID? = nil
    let visibility: String
    let mediaUrl: String?
    let mediaType: String?
    let source: String

    enum CodingKeys: String, CodingKey {
        case authorId = "author_id"
        case message
        case recipientEmail = "recipient_email"
        case recipientPhone = "recipient_phone"
        case recipientName = "recipient_name"
        case recipientId = "recipient_id"
        case visibility
        case mediaUrl = "media_url"
        case mediaType = "media_type"
        case source
    }
}

/// Partial update for an existing appreciation (pending edits).
struct GratitudeUpdate: Encodable {
    var message: String
    var recipientEmail: String?
    var recipientPhone: String?
    var recipientName: String?
    var visibility: String
    var mediaUrl: String?
    var mediaType: String?

    enum CodingKeys: String, CodingKey {
        case message
        case recipientEmail = "recipient_email"
        case recipientPhone = "recipient_phone"
        case recipientName = "recipient_name"
        case visibility
        case mediaUrl = "media_url"
        case mediaType = "media_type"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(message, forKey: .message)
        try c.encode(recipientEmail, forKey: .recipientEmail)
        try c.encode(recipientPhone, forKey: .recipientPhone)
        try c.encode(recipientName, forKey: .recipientName)
        try c.encode(visibility, forKey: .visibility)
        try c.encode(mediaUrl, forKey: .mediaUrl)
        try c.encode(mediaType, forKey: .mediaType)
    }
}

struct AppNotification: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let type: String
    let gratitudeId: UUID?
    let fromUserId: UUID?
    var read: Bool?
    let createdAt: Date?
    var fromUser: Profile?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case gratitudeId = "gratitude_id"
        case fromUserId = "from_user_id"
        case read
        case createdAt = "created_at"
        case fromUser = "from_user"
    }

    var verb: String {
        switch type {
        case "gratitude_pending":
            return "shared appreciation for you"
        case "gratitude_received":
            return "accepted your appreciation"
        case "heart_received", "heart", "reaction":
            return "hearted your appreciation"
        case "gratitude_friday":
            let date = createdAt ?? Date()
            return FridayPrompts.prompt(for: date).headline
        case "pay_it_forward_reminder":
            return "Ready to pay it forward?"
        case "reply":
            return "replied to your appreciation"
        case "competition_winner":
            return "You finished the challenge — unlock $30 to give away to a classroom."
        default:
            return type.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Prefer remote winner copy when available (Notifications UI).
    var displayVerb: String {
        if type == "competition_winner" {
            let body = CompetitionConfigService.cached.winnerNotifyBody
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        return verb
    }
}

struct ProfileStats {
    var sent = 0
    var received = 0
    var inspired = 0   // distinct people who hearted accepted posts you sent or received (excl. self)
}

/// A heart someone left on a post you sent or received — powers the
/// "Inspired" tab on profiles (who was inspired, newest first).
struct Inspiration: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date?
    var user: Profile?
    var gratitude: Gratitude?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case user, gratitude
    }
}

/// Search result from the web app's nonprofit lookup
/// (openthanks.com/api/nonprofits/search, ProPublica-backed).
struct NonprofitOrg: Decodable, Identifiable, Hashable {
    let ein: Int
    let strein: String
    let name: String
    let subName: String?
    let city: String?
    let state: String?
    let website: String?

    enum CodingKeys: String, CodingKey {
        case ein, strein, name, city, state, website
        case subName = "sub_name"
    }

    var id: Int { ein }
    var location: String? {
        let parts = [city, state].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

extension Error {
    /// SwiftUI `.refreshable` / `.task` cancellation — not a real failure.
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}
