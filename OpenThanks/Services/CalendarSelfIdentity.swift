import Foundation

/// Emails + names that belong to the signed-in author — used so calendar
/// gratitude nudges never suggest thanking yourself (including other inboxes).
struct CalendarSelfIdentity: Equatable, Sendable {
    var emails: Set<String>
    /// Lowercased full display names (not single given names — too ambiguous).
    var fullNames: Set<String>

    static let empty = CalendarSelfIdentity(emails: [], fullNames: [])

    private static let rememberedEmailsKey = "calendarSelfEmails.v1"

    var isEmpty: Bool { emails.isEmpty && fullNames.isEmpty }

    mutating func insert(email raw: String?) {
        guard let email = Self.normalizeEmail(raw) else { return }
        emails.insert(email)
    }

    mutating func insert(fullName raw: String?) {
        guard let name = Self.normalizePersonName(raw) else { return }
        fullNames.insert(name)
    }

    mutating func formUnion(_ other: CalendarSelfIdentity) {
        emails.formUnion(other.emails)
        fullNames.formUnion(other.fullNames)
    }

    /// True when this attendee is clearly the author (email alias or same full name).
    func matches(attendee: CalendarAttendee) -> Bool {
        if attendee.isCurrentUser { return true }
        if let email = Self.normalizeEmail(attendee.email), emails.contains(email) {
            return true
        }
        return containsPersonName(attendee.name)
    }

    func containsPersonName(_ raw: String?) -> Bool {
        guard let name = Self.normalizePersonName(raw), !name.isEmpty else { return false }
        return fullNames.contains(name)
    }

    /// Pulls a thank-you topic from a meeting title without naming the author.
    func sanitizedMeetingTopic(_ title: String) -> String? {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for name in fullNames.sorted(by: { $0.count > $1.count }) {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"^"# + escaped + #"\s*[/\-|–—&]\s*"#,
                #"\s*[/\-|–—&]\s*"# + escaped + #"$"#,
                #"\s+(and|with|&)\s+"# + escaped + #"\b"#,
                #"\b"# + escaped + #"\s+(and|with|&)\s+"#,
                #"\b"# + escaped + #"\b"#,
            ]
            for pattern in patterns {
                text = text.replacingOccurrences(
                    of: pattern,
                    with: " ",
                    options: [.regularExpression, .caseInsensitive]
                )
            }
        }

        text = text
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/-|–—&"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let lower = text.lowercased()
        if text.isEmpty
            || lower == "meeting"
            || lower == "1:1"
            || lower == "1-1"
            || lower == "sync"
            || lower == "catch up"
            || lower == "catch-up" {
            return nil
        }
        return text
    }

    static func normalizeEmail(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains(".") else { return nil }
        return email
    }

    static func normalizePersonName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let name = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Require a full name (at least two tokens) so "Alex" doesn't exclude every Alex.
        let parts = name.split(separator: " ")
        guard parts.count >= 2, name.count >= 5 else { return nil }
        return name
    }

    static func rememberedEmails() -> Set<String> {
        let raw = UserDefaults.standard.stringArray(forKey: rememberedEmailsKey) ?? []
        return Set(raw.compactMap(normalizeEmail))
    }

    static func remember(emails: Set<String>) {
        var merged = rememberedEmails()
        merged.formUnion(emails.compactMap(normalizeEmail))
        guard !merged.isEmpty else { return }
        UserDefaults.standard.set(Array(merged).sorted(), forKey: rememberedEmailsKey)
    }

    /// Pure builder for tests and call sites that already gathered inputs.
    static func collect(
        profileEmail: String? = nil,
        profileFullName: String? = nil,
        accountEmail: String? = nil,
        identityEmails: [String] = [],
        googleCalendarEmail: String? = nil,
        remembered: Set<String> = rememberedEmails()
    ) -> CalendarSelfIdentity {
        var identity = CalendarSelfIdentity.empty
        identity.insert(email: profileEmail)
        identity.insert(email: accountEmail)
        identity.insert(email: googleCalendarEmail)
        for email in identityEmails {
            identity.insert(email: email)
        }
        for email in remembered {
            identity.insert(email: email)
        }
        identity.insert(fullName: profileFullName)
        return identity
    }

    /// Live gather from auth + Google Calendar account + remembered aliases.
    @MainActor
    static func collect(from auth: AuthService) async -> CalendarSelfIdentity {
        let profile = auth.currentProfile
        let accountEmail = await auth.currentAccountEmail()
        let identities = await auth.fetchLinkedIdentities()
        let identityEmails = identities.compactMap { identity -> String? in
            identity.identityData?["email"]?.stringValue
        }
        let googleEmail = await GoogleCalendarAuth.cachedAccountEmail()
        var identity = collect(
            profileEmail: profile?.email,
            profileFullName: profile?.fullName ?? profile?.displayName,
            accountEmail: accountEmail,
            identityEmails: identityEmails,
            googleCalendarEmail: googleEmail
        )
        if let full = profile?.fullName {
            identity.insert(fullName: full)
        }
        return identity
    }

    /// Offline path for background refresh (no AuthService).
    static func collectFromCache() -> CalendarSelfIdentity {
        var profileEmail: String?
        var profileName: String?
        if let data = UserDefaults.standard.data(forKey: "cachedProfile.v1"),
           let profile = try? JSONDecoder().decode(Profile.self, from: data) {
            profileEmail = profile.email
            profileName = profile.fullName
        }
        return collect(
            profileEmail: profileEmail,
            profileFullName: profileName,
            googleCalendarEmail: GoogleCalendarAuth.storedAccountEmail()
        )
    }
}
