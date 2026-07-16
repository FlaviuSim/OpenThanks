import Foundation

/// Central configuration. Values below were pulled live from the `open-thanks`
/// Supabase project (dsftvyuzmhlqadhbubgw) on 2026-07-06.
enum AppConfig {
    /// Supabase project URL (verified via management API).
    static let supabaseURL = URL(string: "https://dsftvyuzmhlqadhbubgw.supabase.co")!

    /// Modern publishable key (safe to ship in a client binary; RLS is enabled
    /// on every public table, verified at generation time).
    static let supabaseKey = "sb_publishable_6E3JYy1bWx45o9o9NmDjbg_77tAjxN1"

    /// Storage bucket for photo/video attachments.
    /// ⚠️ UNVERIFIED: confirm the bucket name your web app writes to
    /// (Supabase Studio → Storage). Change this constant if it differs.
    static let mediaBucket = "gratitude-media"

    /// Web app origin used for route-relative media URLs created by openthanks.com.
    static let webAppURL = URL(string: "https://openthanks.com")!

    /// Deep-link scheme used for OAuth (Google) redirects.
    /// Must be registered in Supabase Auth → URL Configuration → Redirect URLs
    /// as: openthanks://auth-callback
    static let redirectURL = URL(string: "openthanks://auth-callback")!

    /// Optional endpoint for the "Make it Warmer" / "Polish for public"
    /// AI rewrite feature. The web app runs this in Next.js API routes, not
    /// Supabase Edge Functions (project has zero edge functions deployed).
    /// Point this at your route, e.g. https://openthanks.com/api/polish,
    /// or leave nil to hide the buttons.
    static let polishEndpoint: URL? = nil

    static func publicStorageURL(for storedPath: String) -> URL? {
        let trimmed = storedPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let path = trimmed.hasPrefix("\(mediaBucket)/")
            ? String(trimmed.dropFirst(mediaBucket.count + 1))
            : trimmed

        var components = URLComponents(url: supabaseURL, resolvingAgainstBaseURL: false)
        components?.path = "/storage/v1/object/public/\(mediaBucket)/\(path)"
        return components?.url
    }

    static func mediaURL(from storedValue: String?) -> URL? {
        guard let storedValue else { return nil }
        let trimmed = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https" {
            return url
        }

        if let url = URL(string: trimmed, relativeTo: webAppURL),
           url.scheme == "http" || url.scheme == "https",
           trimmed.hasPrefix("/") {
            return url.absoluteURL
        }

        if trimmed.hasPrefix("\(mediaBucket)/") {
            return publicStorageURL(for: trimmed)
        }

        return nil
    }
}
