import Foundation

/// Campaign compose query on `openthanks://compose` and `https://openthanks.com/november`.
struct CampaignComposeLink: Equatable, Sendable {
    var id: String
    var day: Int?
}

/// Custom-scheme destinations for widgets and shortcuts.
/// Auth stays at `openthanks://auth-callback`; everything else is routed in-app.
enum WidgetDeepLink {
    static let scheme = "openthanks"

    static var compose: URL {
        URL(string: "\(scheme)://compose")!
    }

    static var received: URL {
        URL(string: "\(scheme)://received")!
    }

    static func gratitude(id: UUID) -> URL {
        URL(string: "\(scheme)://gratitude/\(id.uuidString.lowercased())")!
    }

    static var home: URL {
        URL(string: "\(scheme)://home")!
    }

    enum Destination: Equatable {
        case compose(CampaignComposeLink?)
        case received
        case gratitude(UUID)
        case home
        case notifications
    }

    /// `openthanks://compose?campaign=november-2026&day=N`
    static func campaignLink(from url: URL) -> CampaignComposeLink? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        let id = items.first { $0.name.caseInsensitiveCompare("campaign") == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id, !id.isEmpty else { return nil }
        let rawDay = items.first { $0.name.caseInsensitiveCompare("day") == .orderedSame }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let rawDay, !rawDay.isEmpty, let day = Int(rawDay), (1...31).contains(day) {
            return CampaignComposeLink(id: id, day: day)
        }
        return CampaignComposeLink(id: id, day: nil)
    }

    static func parse(_ url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Supabase OAuth — never treat as a widget destination.
        if host == "auth-callback" || path == "auth-callback" || host.hasPrefix("auth") {
            return nil
        }

        switch host {
        case "compose", "thank", "send":
            return .compose(campaignLink(from: url))
        case "received", "inbox":
            return .received
        case "gratitude":
            if let id = UUID(uuidString: path) {
                return .gratitude(id)
            }
            return .received
        case "notifications":
            return .notifications
        case "home", "":
            if path == "compose" || path == "thank" { return .compose(campaignLink(from: url)) }
            if path == "received" || path == "inbox" { return .received }
            if path.hasPrefix("gratitude/") {
                let idPart = String(path.dropFirst("gratitude/".count))
                if let id = UUID(uuidString: idPart) { return .gratitude(id) }
            }
            if path == "notifications" { return .notifications }
            return .home
        default:
            if path == "compose" { return .compose(campaignLink(from: url)) }
            if path == "received" { return .received }
            if path == "notifications" { return .notifications }
            return nil
        }
    }

    /// True when this URL is the OAuth redirect (must go to AuthService).
    static func isAuthCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        return host == "auth-callback" || path.contains("auth-callback")
    }

    /// Maps content custom-scheme links from the website (`openthanks://claim/…`)
    /// to `https://openthanks.com/…` so Universal Link routing can handle them.
    /// Auth callbacks and widget destinations (`compose`, `home`, …) return nil.
    static func httpsMirror(of url: URL) -> URL? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if isAuthCallback(url) { return nil }
        if parse(url) != nil { return nil }

        let host = (url.host ?? "").lowercased()
        guard !host.isEmpty else { return nil }

        var path = url.path
        if path.isEmpty { path = "/" }
        if !path.hasPrefix("/") { path = "/" + path }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "openthanks.com"
        components.path = "/" + host + (path == "/" ? "" : path)
        components.query = url.query
        return components.url
    }
}
