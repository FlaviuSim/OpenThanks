import Foundation

/// Soft Home reminder when the user finished the calendar gate but never connected
/// Apple or Google. Dismissible with a 14-day snooze — never blocks the app.
@MainActor
@Observable
final class CalendarConnectReminder {
    static let shared = CalendarConnectReminder()

    private static let completedPromptKey = "hasCompletedCalendarPrompt"
    private static let snoozeUntilKey = "calendarConnect.snoozeUntil.v1"
    private static let lastShownAtKey = "calendarConnect.lastShownAt.v1"

    private static let snoozeDays = 14

    /// True when Home should show the dismissible connect banner.
    private(set) var shouldShowBanner = false

    private init() {
        refresh()
    }

    /// Call on Home appear / app foreground.
    func refresh() {
        let completed = UserDefaults.standard.bool(forKey: Self.completedPromptKey)
        let connected = CalendarMeetingAggregator.hasAnyConnectedSource

        guard completed, !connected else {
            shouldShowBanner = false
            return
        }

        if let until = UserDefaults.standard.object(forKey: Self.snoozeUntilKey) as? TimeInterval,
           Date().timeIntervalSince1970 < until {
            shouldShowBanner = false
            return
        }

        shouldShowBanner = true
    }

    func snooze() {
        let until = Date().timeIntervalSince1970 + Double(Self.snoozeDays) * 24 * 60 * 60
        UserDefaults.standard.set(until, forKey: Self.snoozeUntilKey)
        Analytics.capture("calendar_connect_banner_dismissed")
        refresh()
    }

    func trackConnectTapped() {
        Analytics.capture("calendar_connect_banner_tapped")
    }

    /// Call from the banner’s `onAppear` so we only count real Home impressions.
    /// At most once per snooze window (tab switches shouldn’t re-fire).
    func trackBannerShown() {
        guard shouldShowBanner else { return }
        let now = Date().timeIntervalSince1970
        if let last = UserDefaults.standard.object(forKey: Self.lastShownAtKey) as? TimeInterval,
           now - last < Double(Self.snoozeDays) * 24 * 60 * 60 {
            return
        }
        UserDefaults.standard.set(now, forKey: Self.lastShownAtKey)
        Analytics.capture("calendar_connect_banner_shown")
    }
}
