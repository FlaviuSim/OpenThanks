import BackgroundTasks
import Foundation

/// Best-effort late-day refresh so the 8pm calendar nudge can be scheduled
/// even if the user doesn’t open the app.
enum CalendarGratitudeBackgroundRefresh {
    static let taskIdentifier = "com.openthanks.gratitude.calendar-gratitude-refresh"

    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh)
        }
    }

    /// Ask the system for another refresh window (typically afternoon → evening).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        // Prefer late afternoon so today’s meetings have mostly happened.
        let cal = Calendar.current
        let now = Date()
        var earliest = cal.date(bySettingHour: 16, minute: 0, second: 0, of: now) ?? now
        if earliest <= now {
            earliest = now.addingTimeInterval(60 * 60)
        }
        // Don’t schedule more than ~18 hours out.
        if earliest.timeIntervalSince(now) > 18 * 3600 {
            earliest = now.addingTimeInterval(6 * 3600)
        }
        request.earliestBeginDate = earliest
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // System may reject duplicates; safe to ignore.
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule() // chain the next one

        let enabled: Bool
        if UserDefaults.standard.object(forKey: "calendarGratitudeNudgeEnabled") == nil {
            // Default on until the user turns it off in Settings.
            enabled = true
        } else {
            enabled = UserDefaults.standard.bool(forKey: "calendarGratitudeNudgeEnabled")
        }
        let work = Task {
            var emails = Set<String>()
            if let data = UserDefaults.standard.data(forKey: "cachedProfile.v1"),
               let profile = try? JSONDecoder().decode(Profile.self, from: data) {
                if let email = profile.email?.lowercased() {
                    emails.insert(email)
                }
            }
            await NotificationService.refreshCalendarGratitudeNudgeIfEnabled(
                enabled,
                authorId: nil,
                selfEmails: emails
            )
        }

        task.expirationHandler = {
            work.cancel()
        }

        Task {
            _ = await work.result
            task.setTaskCompleted(success: !Task.isCancelled)
        }
    }
}
