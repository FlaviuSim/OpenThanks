import ActivityKit
import Foundation

/// Starts a Lock Screen Live Activity on the grace day after a send, keeps it
/// running until the person posts again (ended immediately) or Apple’s 8-hour
/// active limit (whichever comes first). Streak midnight is still the countdown.
@MainActor
enum StreakLiveActivityController {
    /// Apple’s maximum active Live Activity duration.
    private static let maxActiveDuration: TimeInterval = 8 * 60 * 60

    /// After a successful appreciation: remove today’s reminder immediately and
    /// schedule tomorrow’s Live Activity + morning wake notification.
    static func appreciationDidSend(userId: UUID) async {
        // Dismiss right away — `.default` can leave the Lock Screen tile up for hours.
        await endAll(dismissal: .immediate, markedPosted: true)

        let dates = await fetchSendDates(userId: userId)
        let keep = StreakMath.keepStatus(dates: dates)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        // Trust this send: never restart today’s activity (fetch can lag and look
        // like they still need to post).
        let streakHint = max(keep.streak, 1)
        StreakLiveActivityStore.save(
            StreakLiveActivitySchedule(
                activateDay: tomorrow,
                streakHint: streakHint,
                scheduledAt: .now
            )
        )
        await NotificationService.scheduleStreakLiveActivityWake(on: tomorrow)
    }

    /// Reconcile running Live Activities with streak math. Call on launch,
    /// foreground, notification wake, and after sends.
    static func sync(userId: UUID?) async {
        guard areActivitiesAvailable else {
            await endAll(dismissal: .immediate)
            return
        }

        guard let userId else {
            await endAll(dismissal: .immediate)
            StreakLiveActivityStore.clear()
            await NotificationService.cancelStreakLiveActivityWake()
            return
        }

        let dates = await fetchSendDates(userId: userId)
        let keep = StreakMath.keepStatus(dates: dates)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let schedule = StreakLiveActivityStore.load()

        if keep.needsPostToday {
            // After a send we arm tomorrow. If fetch still looks “at risk” (lag),
            // don’t bring today’s Live Activity back.
            if let schedule, calendar.startOfDay(for: schedule.activateDay) > today {
                await endAll(dismissal: .immediate)
                return
            }
            await ensureStarted(
                streak: keep.streak,
                deadline: keep.deadline,
                reminderDay: today
            )
            // Keep the schedule pointing at today until they post or miss.
            StreakLiveActivityStore.save(
                StreakLiveActivitySchedule(
                    activateDay: today,
                    streakHint: keep.streak,
                    scheduledAt: schedule?.scheduledAt ?? .now
                )
            )
            return
        }

        // Posted today — streak safe; tear down today’s activity immediately and arm tomorrow.
        if keep.isSafeToday {
            await endAll(dismissal: .immediate, markedPosted: true)
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
                StreakLiveActivityStore.save(
                    StreakLiveActivitySchedule(
                        activateDay: tomorrow,
                        streakHint: keep.streak,
                        scheduledAt: .now
                    )
                )
                await NotificationService.scheduleStreakLiveActivityWake(on: tomorrow)
            }
            return
        }

        // Offline / empty history: trust a same-day schedule so we still show the reminder.
        if dates.isEmpty,
           let schedule,
           calendar.isDate(schedule.activateDay, inSameDayAs: today),
           let deadline = calendar.date(byAdding: .day, value: 1, to: today) {
            await ensureStarted(
                streak: max(schedule.streakHint, 1),
                deadline: deadline,
                reminderDay: today
            )
            return
        }

        // Still waiting for tomorrow’s activation day — don’t clear the schedule.
        if let schedule, calendar.startOfDay(for: schedule.activateDay) > today {
            await endAll(dismissal: .immediate)
            return
        }

        // Missed the day (or no streak) — end immediately and clear schedule.
        await endAll(dismissal: .immediate)
        StreakLiveActivityStore.clear()
        await NotificationService.cancelStreakLiveActivityWake()
    }

    /// Notification / cold-start path: start today’s activity if the grace day applies.
    static func handleWakeNotification(userId: UUID?) async {
        await sync(userId: userId)
    }

    // MARK: - Private

    private static var areActivitiesAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private static func fetchSendDates(userId: UUID) async -> [Date] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        let rows = (try? await GratitudeService.sentActivity(authorId: userId, since: since)) ?? []
        return rows.compactMap(\.createdAt)
    }

    /// Active until streak midnight or Apple’s 8-hour cap — whichever is sooner.
    private static func activeUntil(streakDeadline: Date, from start: Date = .now) -> Date {
        let capped = start.addingTimeInterval(maxActiveDuration)
        return min(streakDeadline, capped)
    }

    private static func ensureStarted(streak: Int, deadline: Date, reminderDay: Date) async {
        guard areActivitiesAvailable else { return }
        guard streak > 0 else { return }

        let state = StreakLiveActivityAttributes.ContentState(
            streakCount: streak,
            deadline: deadline,
            postedToday: false
        )

        for activity in Activity<StreakLiveActivityAttributes>.activities {
            let sameDay = Calendar.current.isDate(activity.attributes.reminderDay, inSameDayAs: reminderDay)
            if sameDay {
                // Don’t restart the 8-hour clock on every foreground sync.
                let until: Date
                if let existingStale = activity.content.staleDate, existingStale > Date() {
                    until = min(deadline, existingStale)
                } else {
                    until = activeUntil(streakDeadline: deadline)
                }
                let content = ActivityContent(state: state, staleDate: until)
                await activity.update(content)
                return
            }
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let until = activeUntil(streakDeadline: deadline)
        let content = ActivityContent(state: state, staleDate: until)
        let attributes = StreakLiveActivityAttributes(reminderDay: reminderDay)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            Analytics.capture("streak_live_activity_started", [
                "streak": streak,
                "active_hours": until.timeIntervalSinceNow / 3600,
            ])
            scheduleLocalEnd(at: until, streakDeadline: deadline)
        } catch {
            print("Couldn't start streak Live Activity: \(error.localizedDescription)")
        }
    }

    private static func endAll(dismissal: ActivityUIDismissalPolicy, markedPosted: Bool = false) async {
        for activity in Activity<StreakLiveActivityAttributes>.activities {
            let state = StreakLiveActivityAttributes.ContentState(
                streakCount: activity.content.state.streakCount,
                deadline: activity.content.state.deadline,
                postedToday: markedPosted
            )
            let content = ActivityContent(state: state, staleDate: nil)
            await activity.end(content, dismissalPolicy: dismissal)
        }
    }

    /// End when the 8-hour (or midnight) active window ends. Use `.default`
    /// dismissal so the Lock Screen can keep it up to ~4 more hours (Apple max).
    private static func scheduleLocalEnd(at activeUntil: Date, streakDeadline: Date) {
        let delay = activeUntil.timeIntervalSinceNow
        guard delay > 0, delay <= maxActiveDuration + 60 else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            for activity in Activity<StreakLiveActivityAttributes>.activities {
                if activity.content.state.postedToday { continue }
                // Still within streak day but past Apple’s active window (or past midnight).
                if Date() >= activeUntil || Date() >= streakDeadline {
                    let state = StreakLiveActivityAttributes.ContentState(
                        streakCount: activity.content.state.streakCount,
                        deadline: activity.content.state.deadline,
                        postedToday: false
                    )
                    let content = ActivityContent(state: state, staleDate: nil)
                    // `.default` → Lock Screen can linger up to 4 hours after end.
                    await activity.end(content, dismissalPolicy: .default)
                    Analytics.capture("streak_live_activity_expired", [:])
                }
            }
        }
    }
}
