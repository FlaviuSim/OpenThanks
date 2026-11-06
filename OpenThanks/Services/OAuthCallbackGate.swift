import Foundation

/// Owns the custom-scheme OAuth callback while Google or LinkedIn sign-in is
/// in flight.
///
/// `ASWebAuthenticationSession` returns `openthanks://auth-callback` to
/// `signInWithOAuth`, which exchanges the single-use PKCE code. iOS also
/// delivers that same URL to `onOpenURL`. Forwarding it into
/// `supabase.auth.handle` starts a second exchange. The loser throws
/// (code already used / missing verifier), so a completed Google or LinkedIn
/// sign-in is recorded as `sign_in_failed` and never as `auth_signed_in`.
final class OAuthCallbackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var depth = 0

    /// Hold the callback until `body` returns, including the PKCE exchange
    /// that runs after the browser session hands the URL back.
    func owningAuthCallback<T>(_ body: () async throws -> T) async throws -> T {
        begin()
        defer { end() }
        return try await body()
    }

    func begin() {
        lock.lock()
        depth += 1
        lock.unlock()
    }

    func end() {
        lock.lock()
        if depth > 0 { depth -= 1 }
        lock.unlock()
    }

    /// False only for the in-flight custom-scheme auth callback.
    /// Other links (compose, claim, https) still go to their own handlers.
    func shouldForward(_ url: URL) -> Bool {
        lock.lock()
        let owning = depth > 0
        lock.unlock()
        if owning, Self.isAuthCallback(url) { return false }
        return true
    }

    /// `openthanks://auth-callback` (query or fragment). Same match as
    /// `WidgetDeepLink.isAuthCallback`.
    static func isAuthCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "openthanks" else { return false }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        return host == "auth-callback" || path.contains("auth-callback")
    }
}
