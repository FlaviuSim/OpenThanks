import ActivityKit
import Foundation

/// Lock Screen / Dynamic Island reminder on the grace day after a send:
/// post again before local midnight to keep the streak.
struct StreakLiveActivityAttributes: ActivityAttributes {
    /// Calendar day (start-of-day) this reminder applies to.
    var reminderDay: Date

    struct ContentState: Codable, Hashable, Sendable {
        /// Current send streak length (includes yesterday when still at risk).
        var streakCount: Int
        /// Local midnight that ends the grace window (`startOfDay` tomorrow).
        var deadline: Date
        var postedToday: Bool
    }
}

/// Persisted intent so we can start the Live Activity the morning after a send.
struct StreakLiveActivitySchedule: Codable, Equatable, Sendable {
    /// Start-of-day when the Live Activity should be active.
    var activateDay: Date
    /// Streak length to show if we start before a full sync.
    var streakHint: Int
    /// When this schedule was written (last successful send).
    var scheduledAt: Date
}

enum StreakLiveActivityStore {
    private static let key = "streakLiveActivity.schedule.v1"

    static func load() -> StreakLiveActivitySchedule? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StreakLiveActivitySchedule.self, from: data)
    }

    static func save(_ schedule: StreakLiveActivitySchedule) {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
    }
}
