import Foundation

/// Explicit re-consent for uploading calendar history (incl. notes) to OpenThanks.
enum CalendarServerSyncConsent {
    /// Bump when disclosure text / data scope changes and users must re-accept.
    static let consentVersion = 1
    private static let versionKey = "calendarServerSyncConsent.version"
    private static let atKey = "calendarServerSyncConsent.at"

    static var hasConsented: Bool {
        UserDefaults.standard.integer(forKey: versionKey) >= consentVersion
    }

    static var consentedAt: Date? {
        let t = UserDefaults.standard.double(forKey: atKey)
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    static func recordConsent(at date: Date = Date()) {
        UserDefaults.standard.set(consentVersion, forKey: versionKey)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: atKey)
    }

    static func revoke() {
        UserDefaults.standard.removeObject(forKey: versionKey)
        UserDefaults.standard.removeObject(forKey: atKey)
    }

    static let disclosureTitle = "Sync calendar history for thank-you suggestions"

    static let disclosureBody = """
    OpenThanks can sync your calendar history (as available, up to about 10 years) — including event titles, times, attendees, and meeting notes/descriptions — to our servers. We use that only to suggest people you may want to thank and to help draft messages. Notes are never shown to other users. You can disconnect or delete calendar data anytime in Settings.
    """
}
