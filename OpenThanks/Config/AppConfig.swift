import Foundation

/// Central configuration. Values below were pulled live from the `open-thanks`
/// Supabase project (dsftvyuzmhlqadhbubgw) on 2026-07-06.
enum AppConfig {
    /// Supabase API via custom domain (same project as `*.supabase.co`).
    /// Keeps Google/OAuth and API calls on db.openthanks.com instead of the
    /// long project-ref host.
    static let supabaseURL = URL(string: "https://db.openthanks.com")!

    /// Modern publishable key (safe to ship in a client binary; RLS is enabled
    /// on every public table, verified at generation time).
    static let supabaseKey = "sb_publishable_6E3JYy1bWx45o9o9NmDjbg_77tAjxN1"

    /// Storage buckets for profile photos and post attachments.
    static let avatarBucket = "avatars"
    static let mediaBucket = "gratitude-media"

    /// Web app origin used for route-relative media URLs created by openthanks.com.
    static let webAppURL = URL(string: "https://openthanks.com")!

    /// Custom-scheme callback ASWebAuthenticationSession listens for.
    /// Also register in Supabase Auth → URL Configuration → Redirect URLs.
    static let redirectURL = URL(string: "openthanks://auth-callback")!

    /// HTTPS OAuth lander on the website. Supabase redirects here after Google/LinkedIn;
    /// the page (or iOS 17.4+ https callback) hands the PKCE `code` back to the app.
    /// Must be listed in Supabase Redirect URLs: https://openthanks.com/auth/mobile
    static let oauthRedirectURL = URL(string: "https://openthanks.com/auth/mobile")!

    /// Google Cloud **iOS** OAuth client ID for Calendar readonly (separate from Supabase Google login).
    /// Create Credentials → OAuth client ID → Application type **iOS**, bundle ID `com.openthanks.gratitude`.
    /// Web clients cannot use custom-scheme redirects; see README.
    static let googleCalendarClientID = "55218854228-c40e4qrr04u042rbaoeaq4dhdpq53jgu.apps.googleusercontent.com"

    /// Google’s iOS redirect: `{reversed-client-id}:/oauthredirect`.
    /// Also register the reversed client ID as a URL scheme in Info.plist / project.yml.
    static var googleCalendarRedirectURL: URL {
        URL(string: "\(googleCalendarReversedClientID):/oauthredirect")!
    }

    /// Scheme ASWebAuthenticationSession listens for (reversed client ID).
    static var googleCalendarURLScheme: String { googleCalendarReversedClientID }

    /// `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
    static var googleCalendarReversedClientID: String {
        let suffix = ".apps.googleusercontent.com"
        let id = googleCalendarClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = id.hasSuffix(suffix) ? String(id.dropLast(suffix.count)) : id
        return "com.googleusercontent.apps.\(prefix)"
    }

    /// Optional legacy endpoint — unused; compose uses on-device Apple Intelligence.
    static let polishEndpoint: URL? = nil

    /// PostHog product analytics (same project as openthanks.com).
    /// Client project token — safe in the app binary; mirrors NEXT_PUBLIC_POSTHOG_KEY.
    static let postHogKey = "phc_tDCoDmFjVxnMikoRQ3EAXP5kgz5EJq9pMTxsGkmLvkXq"
    static let postHogHost = "https://us.i.posthog.com"

    static func publicStorageURL(for storedPath: String, bucket: String = mediaBucket) -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let path = trimmed.hasPrefix("\(bucket)/")
            ? String(trimmed.dropFirst(bucket.count + 1))
            : trimmed

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/storage/v1/object/public/\(bucket)/\(path)"
        return components?.url
    }

    static func mediaURL(from storedValue: String?) -> URL? {
        guard let storedValue else { return nil }
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return url
        }

        // Web app stores private Vercel Blob paths as /api/file?pathname=...
        if trimmed.hasPrefix("/") {
            return URL(string: trimmed, relativeTo: webAppURL)?.absoluteURL
        }

        if trimmed.hasPrefix("\(avatarBucket)/") {
            return publicStorageURL(for: trimmed, bucket: avatarBucket)
        }

        if trimmed.hasPrefix("\(mediaBucket)/") {
            return publicStorageURL(for: trimmed, bucket: mediaBucket)
        }

        return nil
    }
}
