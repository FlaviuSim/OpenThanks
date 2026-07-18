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

        var id: String {
            switch self {
            case .claim(let token): "claim-\(token.uuidString)"
            case .gratitude(let id): "gratitude-\(id.uuidString)"
            case .slug(let slug): "slug-\(slug)"
            case .profile(let username): "profile-\(username)"
            }
        }
    }

    private static let hosts: Set<String> = ["openthanks.com", "www.openthanks.com"]

    private static let reservedRoots: Set<String> = [
        "auth", "api", "feed", "pending", "notifications", "donate",
        "profile", "privacy", "terms", "unsubscribe", "claim-appreciation",
        "claim", "for", "gratitude", "ingest", "_next",
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
        guard Self.isUniversalLink(url),
              let parsed = Self.parse(url)
        else { return false }
        destination = parsed
        return true
    }

    func clear() {
        destination = nil
    }

    static func parse(_ url: URL) -> Destination? {
        let parts = url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }
        guard let first = parts.first?.lowercased() else { return nil }

        switch first {
        case "claim":
            guard parts.count >= 2, let token = UUID(uuidString: parts[1]) else { return nil }
            return .claim(token: token)
        case "gratitude":
            guard parts.count >= 2 else { return nil }
            let idPart = parts[1].lowercased()
            if idPart == "new" { return nil }
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            return .gratitude(id: id)
        case "for":
            guard parts.count >= 2 else { return nil }
            let slug = parts.dropFirst().joined(separator: "/")
            guard !slug.isEmpty else { return nil }
            return .slug(slug)
        default:
            guard parts.count == 1,
                  !reservedRoots.contains(first),
                  isPlausibleUsername(parts[0])
            else { return nil }
            return .profile(username: parts[0].lowercased())
        }
    }

    private static func isPlausibleUsername(_ value: String) -> Bool {
        let handle = value.lowercased()
        guard (2...32).contains(handle.count) else { return false }
        return handle.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
        }
    }
}
