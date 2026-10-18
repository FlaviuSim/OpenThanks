import Foundation

/// Queues deferred notification / calendar prompts after send, accept, or calendar connect.
/// Never blocks first login — RootView only shows calendar on the 3rd main-app open.
@MainActor
@Observable
final class PermissionPromptScheduler {
    static let shared = PermissionPromptScheduler()

    enum Prompt: Equatable {
        /// Receive + accept-confirm pitch after send/accept.
        case notificationsAppreciation(source: String)
        /// Calendar evening-nudge pitch after calendar connect without push auth.
        case notificationsAfterCalendar(source: String)
        /// Calendar connect sheet after appreciation (or when queued behind notifs).
        case calendar(source: String)
    }

    private static let openCountKey = "mainAppOpenCount"
    private static let enteredOnceKey = "hasEnteredMainAppOnce"
    private static let completedNotificationKey = "hasCompletedNotificationPrompt"
    private static let completedCalendarKey = "hasCompletedCalendarPrompt"
    private static let appreciationCalendarCooldownKey = "permissionPrompt.calendarAppreciationCooldownUntil.v1"
    private static let appreciationCalendarCooldownHours: TimeInterval = 24 * 60 * 60

    /// Sheet the main app should present (one at a time).
    private(set) var pending: Prompt?

    /// When calendar was skipped/deferred during an appreciation sequence, offer it next.
    private var queuedCalendarSource: String?

    private init() {}

    // MARK: - Open count (Siri = 2nd open, calendar gate = 3rd)

    /// Current main-app open count (migrates legacy `hasEnteredMainAppOnce`).
    static var mainAppOpenCount: Int {
        migrateOpenCountIfNeeded()
        return UserDefaults.standard.integer(forKey: openCountKey)
    }

    /// Call once per process when HomeGate first reaches `.ready`.
    @discardableResult
    static func recordMainAppOpenIfNeeded(processAlreadyCounted: inout Bool) -> Int {
        migrateOpenCountIfNeeded()
        guard !processAlreadyCounted else {
            return UserDefaults.standard.integer(forKey: openCountKey)
        }
        processAlreadyCounted = true
        let next = UserDefaults.standard.integer(forKey: openCountKey) + 1
        UserDefaults.standard.set(next, forKey: openCountKey)
        if next >= 1 {
            UserDefaults.standard.set(true, forKey: enteredOnceKey)
        }
        return next
    }

    static func migrateOpenCountIfNeeded() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: openCountKey)
        if count == 0, defaults.bool(forKey: enteredOnceKey) {
            defaults.set(1, forKey: openCountKey)
        }
    }

    /// Full-screen calendar on 3rd+ open when still disconnected and gate not finished.
    static var shouldShowDeferredCalendarGate: Bool {
        migrateOpenCountIfNeeded()
        guard !UserDefaults.standard.bool(forKey: completedCalendarKey) else { return false }
        guard !CalendarMeetingAggregator.hasAnyConnectedSource else { return false }
        return defaultsOpenCount >= 3
    }

    private static var defaultsOpenCount: Int {
        UserDefaults.standard.integer(forKey: openCountKey)
    }

    // MARK: - Scheduling

    /// After a successful send or accept (call once the prior sheet has settled).
    func scheduleAfterAppreciation(source: String) {
        if shouldOfferNotificationAppreciationPrompt {
            pending = .notificationsAppreciation(source: source)
            if shouldOfferCalendarAfterAppreciation {
                queuedCalendarSource = source
            }
            return
        }
        if shouldOfferCalendarAfterAppreciation {
            pending = .calendar(source: source)
        }
    }

    /// After calendar connect succeeds without notification authorization.
    func scheduleNotificationsAfterCalendar(source: String) {
        pending = .notificationsAfterCalendar(source: source)
    }

    func clearPending() {
        pending = nil
    }

    /// Call when the current sheet finishes so a queued calendar prompt can follow.
    func advanceAfterFinishing(_ finished: Prompt) {
        switch finished {
        case .notificationsAppreciation:
            if let source = queuedCalendarSource, shouldOfferCalendarAfterAppreciation {
                queuedCalendarSource = nil
                // Swap in place so the sheet stays presented.
                pending = .calendar(source: source)
            } else {
                queuedCalendarSource = nil
                pending = nil
            }
        case .notificationsAfterCalendar, .calendar:
            queuedCalendarSource = nil
            pending = nil
        }
    }

    func markNotificationPromptCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedNotificationKey)
    }

    func markCalendarPromptCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedCalendarKey)
    }

    /// Soft cooldown after declining a post-appreciation calendar sheet (still re-asks later).
    func snoozeAppreciationCalendarPrompt() {
        let until = Date().timeIntervalSince1970 + Self.appreciationCalendarCooldownHours
        UserDefaults.standard.set(until, forKey: Self.appreciationCalendarCooldownKey)
    }

    // MARK: - Eligibility

    var shouldOfferNotificationAppreciationPrompt: Bool {
        !UserDefaults.standard.bool(forKey: Self.completedNotificationKey)
    }

    var shouldOfferCalendarAfterAppreciation: Bool {
        guard !CalendarMeetingAggregator.hasAnyConnectedSource else { return false }
        if let until = UserDefaults.standard.object(forKey: Self.appreciationCalendarCooldownKey) as? TimeInterval,
           Date().timeIntervalSince1970 < until {
            return false
        }
        return true
    }
}
