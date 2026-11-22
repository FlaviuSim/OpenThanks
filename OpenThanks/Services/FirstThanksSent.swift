import Foundation
import Observation

/// Device memory of "this person has sent a thank-you."
///
/// The send counter (`EnjoymentPrompt.successfulSendCount`) covers creates on
/// this phone. `sentKey` covers a send we learned about from another path
/// (Watch, or a row already on the server) without firing `appreciation_submitted`
/// a second time.
enum FirstThanksSent {
    static let sentKey = "firstThanks.hasSentThankYou.v1"

    static func hasSent(in defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: sentKey) { return true }
        return defaults.integer(forKey: EnjoymentPrompt.successfulSendCountKey) > 0
    }

    static func markSent(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: sentKey) else { return }
        defaults.set(true, forKey: sentKey)
    }
}

/// In-memory visit number so Home can refresh when a new visit starts.
@MainActor
@Observable
final class AppVisitCenter {
    static let shared = AppVisitCenter()

    private(set) var number: Int
    private(set) var lastHomeViewAt: Date?

    private init() {
        // Count this arrival before the first Home frame, so an empty My Feed
        // can keep the first-thanks card instead of bouncing to World.
        number = AppVisit.recordReturn(in: .standard)
    }

    @discardableResult
    func recordReturn(now: Date = Date(), calendar: Calendar = .current) -> Int {
        number = AppVisit.recordReturn(in: .standard, now: now, calendar: calendar)
        return number
    }

    func noteActivity(now: Date = Date()) {
        AppVisit.noteActivity(in: .standard, now: now)
    }

    /// Shared across Home's appear, foreground, and tab re-tap.
    func claimHomeView(force: Bool, now: Date = Date()) -> Bool {
        let allow = HomeScreenView.shouldCapture(
            lastCapturedAt: lastHomeViewAt,
            now: now,
            force: force
        )
        guard allow else { return false }
        lastHomeViewAt = now
        return true
    }
}
