import Foundation

/// US Thanksgiving week in a local time zone.
///
/// Thanksgiving is the fourth Thursday of November (Gregorian). The seasonal
/// window is the Monday before that Thursday through the following Sunday,
/// inclusive. Instants are compared in the calendar's time zone, so a Sunday
/// evening on the East Coast stays inside the window even when UTC has already
/// rolled to Monday.
///
/// Keep this file identical to
/// `OpenThanksTests/Sources/ThanksgivingWindow/ThanksgivingWindow.swift`.
enum ThanksgivingWindow {
    struct Span: Equatable, Sendable {
        /// Start of the Monday before Thanksgiving. Inclusive.
        var start: Date
        /// Start of the Monday after Thanksgiving. Exclusive, so Sunday 11:59pm is inside.
        var end: Date
    }

    /// Gregorian calendar pinned to `timeZone`. US Thanksgiving is a civil
    /// Gregorian date, even if the device calendar uses another identifier.
    static func gregorian(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func thanksgiving(year: Int, timeZone: TimeZone) -> Date? {
        let calendar = gregorian(timeZone: timeZone)
        var parts = DateComponents()
        parts.calendar = calendar
        parts.timeZone = timeZone
        parts.year = year
        parts.month = 11
        parts.day = 1
        guard let novemberFirst = calendar.date(from: parts) else { return nil }
        // Gregorian weekday: Sunday = 1 … Thursday = 5.
        let weekday = calendar.component(.weekday, from: novemberFirst)
        let daysUntilThursday = (5 - weekday + 7) % 7
        guard
            let firstThursday = calendar.date(byAdding: .day, value: daysUntilThursday, to: novemberFirst),
            let fourthThursday = calendar.date(byAdding: .day, value: 21, to: firstThursday)
        else { return nil }
        return calendar.startOfDay(for: fourthThursday)
    }

    static func span(year: Int, timeZone: TimeZone) -> Span? {
        let calendar = gregorian(timeZone: timeZone)
        guard let thanksgiving = thanksgiving(year: year, timeZone: timeZone) else { return nil }
        guard
            let monday = calendar.date(byAdding: .day, value: -3, to: thanksgiving),
            let nextMonday = calendar.date(byAdding: .day, value: 4, to: thanksgiving)
        else { return nil }
        return Span(start: monday, end: nextMonday)
    }

    static func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let gregorian = gregorian(timeZone: calendar.timeZone)
        let year = gregorian.component(.year, from: date)
        guard let span = span(year: year, timeZone: calendar.timeZone) else { return false }
        return date >= span.start && date < span.end
    }
}

/// Debug preview for the seasonal theme. `automatic` follows ``ThanksgivingWindow``.
enum ThanksgivingThemeOverride: String, Equatable, Sendable, CaseIterable {
    case automatic
    case on
    case off

    static let defaultsKey = "thanksgivingThemeOverride"
}

enum ThanksgivingThemeGate {
    static func isActive(
        at date: Date,
        calendar: Calendar = .current,
        override: ThanksgivingThemeOverride
    ) -> Bool {
        switch override {
        case .on:
            return true
        case .off:
            return false
        case .automatic:
            return ThanksgivingWindow.contains(date, calendar: calendar)
        }
    }
}

/// What to do with the alternate Home Screen icon.
///
/// `setAlternateIconName` always presents a system alert, and this app already
/// lets people pick Ember, Dawn, or Night. The seasonal icon is opt-in during
/// the window. After the window, if they accepted it and it is still active,
/// restore the icon they had before. Never switch it on automatically.
enum ThanksgivingIconAction: Equatable, Sendable {
    case none
    case clearOptIn
    /// `nil` restores the primary icon.
    case setAlternateIcon(String?)
}

enum ThanksgivingIconPolicy {
    static let seasonalAlternateIconName = "AppIcon-Thanksgiving"

    static func shouldOffer(
        themeActive: Bool,
        supportsAlternateIcons: Bool,
        dismissedYear: Int?,
        seasonYear: Int,
        alreadyUsingSeasonal: Bool
    ) -> Bool {
        guard themeActive, supportsAlternateIcons, !alreadyUsingSeasonal else { return false }
        return dismissedYear != seasonYear
    }

    static func action(
        themeActive: Bool,
        optedIn: Bool,
        previousAlternateIconName: String?,
        activeAlternateIconName: String?
    ) -> ThanksgivingIconAction {
        guard optedIn else { return .none }
        let usingSeasonal = activeAlternateIconName == seasonalAlternateIconName
        if themeActive {
            return .none
        }
        guard usingSeasonal else { return .clearOptIn }
        let target: String? = {
            guard let previousAlternateIconName, !previousAlternateIconName.isEmpty else { return nil }
            return previousAlternateIconName
        }()
        if target == seasonalAlternateIconName || target == activeAlternateIconName {
            return .clearOptIn
        }
        return .setAlternateIcon(target)
    }
}
