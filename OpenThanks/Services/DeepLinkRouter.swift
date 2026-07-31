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
        case profile(username: String)
        /// Author's Pending Appreciations (optional `?resend=` highlight).
        case pendingSent(resendId: UUID?)

        var id: String {
            switch self {
            case .claim(let token): "claim-\(token.uuidString)"
            case .gratitude(let id): "gratitude-\(id.uuidString)"
            case .slug(let slug): "slug-\(slug)"
            case .profile(let username): "profile-\(username)"
            case .pendingSent(let resendId):
                "pending-sent-\(resendId?.uuidString ?? "all")"
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

        guard let parsed = Self.parse(url) else { return false }
        destination = parsed
        return true
    }

    func clear() {
        destination = nil
    }

    /// `/gratitude/new` opens the create-appreciation sheet (not a detail cover).
    static func isComposePath(_ url: URL) -> Bool {
        let parts = pathParts(url)
        guard parts.count >= 2 else { return false }
        return parts[0].lowercased() == "gratitude" && parts[1].lowercased() == "new"
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
        default:
            guard parts.count == 1,
                  !reservedRoots.contains(first),
                  isPlausibleUsername(parts[0])
            else { return nil }
            return .profile(username: parts[0].lowercased())
        }
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
