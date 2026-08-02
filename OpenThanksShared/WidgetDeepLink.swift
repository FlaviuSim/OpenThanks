import Foundation

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

    static var home: URL {
        URL(string: "\(scheme)://home")!
    }

    enum Destination: Equatable {
        case compose
        case received
        case home
        case notifications
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
            return .compose
        case "received", "inbox":
            return .received
        case "notifications":
            return .notifications
        case "home", "":
            if path == "compose" || path == "thank" { return .compose }
            if path == "received" || path == "inbox" { return .received }
            if path == "notifications" { return .notifications }
            return .home
        default:
            if path == "compose" { return .compose }
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
}
