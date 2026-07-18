import Foundation

/// Central configuration. Values below were pulled live from the `open-thanks`
/// Supabase project (dsftvyuzmhlqadhbubgw) on 2026-07-06.
enum AppConfig {
    /// Supabase project URL (verified via management API).
    static let supabaseURL = URL(string: "https://dsftvyuzmhlqadhbubgw.supabase.co")!

    /// Modern publishable key (safe to ship in a client binary; RLS is enabled
    /// on every public table, verified at generation time).
    static let supabaseKey = "sb_publishable_6E3JYy1bWx45o9o9NmDjbg_77tAjxN1"

    /// Storage buckets for profile photos and post attachments.
    static let avatarBucket = "avatars"
    static let mediaBucket = "gratitude-media"

    /// Web app origin used for route-relative media URLs created by openthanks.com.
    static let webAppURL = URL(string: "https://openthanks.com")!

    /// Deep-link scheme used for OAuth (Google) redirects.
    /// Must be registered in Supabase Auth → URL Configuration → Redirect URLs
    /// as: openthanks://auth-callback
    static let redirectURL = URL(string: "openthanks://auth-callback")!

    /// Optional legacy endpoint — unused; compose uses on-device Apple Intelligence.
    static let polishEndpoint: URL? = nil

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
