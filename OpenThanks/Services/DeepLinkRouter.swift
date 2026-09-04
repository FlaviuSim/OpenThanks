import Foundation
import Observation

/// Parses HTTPS Universal Links (`openthanks.com` / `www`) into in-app destinations.
/// Custom scheme `openthanks://` stays reserved for Supabase auth.
@Observable
@MainActor
final class DeepLinkRouter {
    enum Destination: Identifiable, Equatable {
        case claim(token: UUID)
        case gratitude(id: UUID)
        case slug(String)
        case profile(username: String, tab: ProfileTab?)
        /// `/profile/{uuid}` (email fallback when username is missing).
        case profileId(id: UUID, tab: ProfileTab?)
        /// Author's Pending Appreciations (optional `?resend=` highlight).
        case pendingSent(resendId: UUID?)

        var id: String {
            switch self {
            case .claim(let token): "claim-\(token.uuidString)"
            case .gratitude(let id): "gratitude-\(id.uuidString)"
            case .slug(let slug): "slug-\(slug)"
            case .profile(let username, let tab):
                "profile-\(username)-\(tab?.rawValue ?? "default")"
            case .profileId(let id, let tab):
                "profile-id-\(id.uuidString)-\(tab?.rawValue ?? "default")"
            case .pendingSent(let resendId):
                "pending-sent-\(resendId?.uuidString ?? "all")"
            }
        }
    }

    enum ProfileTab: String, Equatable {
        case received
        case given
        case inspired
        case ripple

        var profileSection: UserProfileView.Section {
            switch self {
            case .received: .received
            case .given: .sent
            case .inspired, .ripple: .ripple
            }
        }
    }

    private static let hosts: Set<String> = ["openthanks.com", "www.openthanks.com"]

    private static let reservedRoots: Set<String> = [
        "auth", "api", "feed", "pending", "sent", "notifications", "donate",
        "profile", "privacy", "terms", "unsubscribe", "claim-appreciation",
        "claim", "for", "gratitude", "ingest", "_next", "competition",
    ]

    var destination: Destination?
    /// When set, the next appreciation deep-link cover shows a pay-it-forward prompt
    /// (used after accepting via a claim link).
    var payItForwardFromName: String?
    /// Parent appreciation id for ripple attribution when the nudge opens compose.
    var payItForwardParentId: UUID?

    static func isUniversalLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased()
        else { return false }
        return hosts.contains(host)
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard Self.isUniversalLink(url) else { return false }

        // Same destination as web `/gratitude/new` (Friday email, share CTAs, etc.).
        if Self.isComposePath(url) {
            Self.queueCompose(from: url)
            return true
        }

        // Sunday hearts digest + other email CTAs → Notifications tab.
        if Self.isNotificationsPath(url) {
            TabLaunchBridge.shared.queue(.notifications)
            return true
        }

        guard let parsed = Self.parse(url) else { return false }
        destination = parsed
        return true
    }

    func clear() {
        destination = nil
        payItForwardFromName = nil
        payItForwardParentId = nil
    }

    /// Replace the current deep link (e.g. `/claim/{token}`) with the public
    /// appreciation page (`/for/{slug}` or `/gratitude/{id}`).
    func openAppreciation(
        _ gratitude: Gratitude,
        payItForwardFromName: String? = nil
    ) {
        // Swap the cover first; defer the nudge so it presents on the new page.
        self.payItForwardFromName = nil
        self.payItForwardParentId = nil
        if let slug = gratitude.slug?.trimmingCharacters(in: .whitespacesAndNewlines),
           !slug.isEmpty {
            destination = .slug(slug)
        } else {
            destination = .gratitude(id: gratitude.id)
        }
        guard let name = payItForwardFromName else { return }
        let openedId = gratitude.id
        let openedSlug = gratitude.slug
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            switch destination {
            case .gratitude(let id) where id == openedId:
                self.payItForwardParentId = openedId
                self.payItForwardFromName = name
            case .slug(let slug) where slug == openedSlug:
                self.payItForwardParentId = openedId
                self.payItForwardFromName = name
            default:
                break
            }
        }
    }

    /// `/gratitude/new` opens the create-appreciation sheet (not a detail cover).
    static func isComposePath(_ url: URL) -> Bool {
        let parts = pathParts(url)
        guard parts.count >= 2 else { return false }
        return parts[0].lowercased() == "gratitude" && parts[1].lowercased() == "new"
    }

    /// `/notifications` opens the in-app Notifications tab.
    static func isNotificationsPath(_ url: URL) -> Bool {
        let parts = pathParts(url)
        guard let first = parts.first?.lowercased() else { return false }
        return first == "notifications"
    }

    static func queueCompose(from url: URL) {
        let source = queryValue(url, name: "source")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = queryValue(url, name: "for")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let analyticsSource: String
        if let source, !source.isEmpty {
            analyticsSource = source
        } else {
            analyticsSource = "universal_link_compose"
        }
        ComposeLaunchBridge.shared.queue(
            recipientName: (recipient?.isEmpty == false) ? recipient : nil,
            analyticsSource: analyticsSource
        )
    }

    static func parse(_ url: URL) -> Destination? {
        let parts = pathParts(url)
        guard let first = parts.first?.lowercased() else { return nil }

        switch first {
        case "claim":
            guard parts.count >= 2, let token = UUID(uuidString: parts[1]) else { return nil }
            return .claim(token: token)
        case "gratitude":
            guard parts.count >= 2 else { return nil }
            let idPart = parts[1].lowercased()
            // Handled separately via `isComposePath` → ComposeLaunchBridge.
            if idPart == "new" { return nil }
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            return .gratitude(id: id)
        case "for":
            guard parts.count >= 2 else { return nil }
            let slug = parts.dropFirst().joined(separator: "/")
            guard !slug.isEmpty else { return nil }
            return .slug(slug)
        case "pending", "sent":
            // Author reminder emails: /pending?resend=<id> or legacy /sent?resend=<id>
            let resendId = UUID(uuidString: queryValue(url, name: "resend") ?? "")
            return .pendingSent(resendId: resendId)
        case "profile":
            guard parts.count >= 2, let id = UUID(uuidString: parts[1]) else { return nil }
            return .profileId(id: id, tab: profileTab(from: url))
        default:
            guard parts.count == 1,
                  !reservedRoots.contains(first),
                  isPlausibleUsername(parts[0])
            else { return nil }
            return .profile(username: parts[0].lowercased(), tab: profileTab(from: url))
        }
    }

    /// `?tab=inspired` (or given/received) on profile URLs.
    static func profileTab(from url: URL) -> ProfileTab? {
        guard let value = queryValue(url, name: "tab")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !value.isEmpty
        else { return nil }
        return ProfileTab(rawValue: value)
    }

    /// Weekly hearts email: `/{username}?tab=inspired` or `/profile/{id}?tab=inspired`
    /// for the signed-in user should switch the Profile tab instead of a cover.
    static func shouldOpenOwnInspiredTab(
        _ url: URL,
        username: String?,
        userId: UUID?
    ) -> Bool {
        guard isUniversalLink(url) else { return false }
        guard profileTab(from: url) == .inspired || profileTab(from: url) == .ripple else { return false }
        let parts = pathParts(url)
        guard let first = parts.first?.lowercased() else { return false }
        if first == "profile" {
            guard parts.count >= 2, let id = UUID(uuidString: parts[1]) else { return false }
            return userId == id
        }
        guard parts.count == 1, isPlausibleUsername(parts[0]) else { return false }
        guard let username, !username.isEmpty else { return false }
        return username.lowercased() == parts[0].lowercased()
    }

    private static func pathParts(_ url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }
    }

    private static func queryValue(_ url: URL, name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name.lowercased() == name.lowercased() })?
            .value
    }

    private static func isPlausibleUsername(_ value: String) -> Bool {
        let handle = value.lowercased()
        guard (2...32).contains(handle.count) else { return false }
        return handle.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
