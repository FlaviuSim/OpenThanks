import Foundation
import UIKit
import UserNotifications
import Supabase

enum NotificationService {
    private static let fridayReminderId = "friday-gratitude-reminder"

    /// Local Gratitude Friday reminder — tap opens compose.
    static let fridayReminderTypeKey = "type"
    static let fridayReminderTypeValue = "gratitude_friday"

    struct DevicePushToken: Encodable {
        let userId: UUID
        let token: String
        let platform: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case platform
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Already granted (including provisional / ephemeral).
    static func isAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// System has already answered — no custom prompt needed.
    static func hasResolvedAuthorization() async -> Bool {
        await authorizationStatus() != .notDetermined
    }

    static func requestAuthorizationAndRegisterForPushes() async -> Bool {
        do {
            let status = await authorizationStatus()
            let granted: Bool
            if status == .notDetermined {
                granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .badge, .sound])
            } else {
                granted = status == .authorized || status == .provisional || status == .ephemeral
            }
            guard granted else { return false }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return true
        } catch {
            return false
        }
    }

    /// Schedules the next Friday 9:00 AM local notification with that week's
    /// rotating question (same bank as the web Friday email).
    /// Call again on app launch so copy stays current week to week.
    static func enableFridayReminder() async -> Bool {
        guard await requestAuthorizationAndRegisterForPushes() else { return false }

        await disableFridayReminder()

        let fireDate = FridayPrompts.nextFridayNineAM()
        let prompt = FridayPrompts.prompt(for: fireDate)

        let content = UNMutableNotificationContent()
        content.title = prompt.headline
        content.body = prompt.body
        content.sound = .default
        content.userInfo = [
            fridayReminderTypeKey: fridayReminderTypeValue,
        ]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: fridayReminderId,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    /// Re-schedules only if the toggle is on and permission is granted.
    static func refreshFridayReminderIfEnabled(_ enabled: Bool) async {
        guard enabled else {
            await disableFridayReminder()
            return
        }
        guard await isAuthorized() else { return }
        _ = await enableFridayReminder()
    }

    static func disableFridayReminder() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [fridayReminderId])
    }

    // MARK: Calendar evening gratitude nudge

    private static let calendarNudgeId = "calendar-gratitude-nudge"
    static let calendarNudgeTypeValue = "calendar_gratitude_nudge"
    static let calendarNudgeNameKey = "recipientName"
    static let calendarNudgeEmailKey = "recipientEmail"
    static let calendarNudgeMessageKey = "messageDraft"
    static let calendarNudgeMeetingKey = "meetingTitle"
    static let calendarNudgeProfileIdKey = "profileId"

    /// Weekday 8:00 PM local — only when today’s calendar yields a strong candidate.
    static func refreshCalendarGratitudeNudgeIfEnabled(
        _ enabled: Bool,
        authorId: UUID? = nil,
        selfEmails: Set<String> = []
    ) async {
        guard enabled else {
            await disableCalendarGratitudeNudge()
            return
        }
        guard await isAuthorized() else {
            await disableCalendarGratitudeNudge()
            return
        }
        guard CalendarMeetingService.hasFullAccess else {
            await disableCalendarGratitudeNudge()
            return
        }

        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        if weekday == 1 || weekday == 7 {
            await disableCalendarGratitudeNudge()
            return
        }

        guard let eightPM = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now) else {
            await disableCalendarGratitudeNudge()
            return
        }

        // Past tonight’s window — clear and wait for tomorrow’s refresh.
        if now >= eightPM {
            await disableCalendarGratitudeNudge()
            return
        }

        let resolvedAuthorId: UUID?
        if let authorId {
            resolvedAuthorId = authorId
        } else if let session = try? await supabase.auth.session {
            resolvedAuthorId = session.user.id
        } else {
            resolvedAuthorId = nil
        }

        guard let nudge = await GratitudeOpportunityRanker.pickNudge(
            for: now,
            authorId: resolvedAuthorId,
            selfEmails: selfEmails,
            now: now
        ) else {
            await disableCalendarGratitudeNudge()
            return
        }

        await disableCalendarGratitudeNudge()

        let content = UNMutableNotificationContent()
        content.title = "Someone to thank tonight?"
        let meetingBit = nudge.meetingTitle.count <= 40
            ? " about \(nudge.meetingTitle)"
            : ""
        content.body = "You met with \(nudge.personName)\(meetingBit) — send a quick thanks?"
        content.sound = .default

        var info: [String: Any] = [
            fridayReminderTypeKey: calendarNudgeTypeValue,
            calendarNudgeNameKey: nudge.personName,
            calendarNudgeMeetingKey: nudge.meetingTitle,
        ]
        if let email = nudge.email {
            info[calendarNudgeEmailKey] = email
        }
        if let draft = nudge.messageDraft {
            info[calendarNudgeMessageKey] = draft
        }
        if let profileId = nudge.profile?.id {
            info[calendarNudgeProfileIdKey] = profileId.uuidString
        }
        content.userInfo = info

        let components = cal.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: eightPM
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: calendarNudgeId,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Leave cancelled if scheduling fails.
        }
    }

    /// Enables the evening nudge: notification permission + calendar access, then schedule.
    static func enableCalendarGratitudeNudge(
        authorId: UUID?,
        selfEmails: Set<String>
    ) async -> Bool {
        guard await requestAuthorizationAndRegisterForPushes() else { return false }
        guard await CalendarMeetingService.requestAccess() else { return false }
        await refreshCalendarGratitudeNudgeIfEnabled(
            true,
            authorId: authorId,
            selfEmails: selfEmails
        )
        return true
    }

    static func disableCalendarGratitudeNudge() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [calendarNudgeId])
    }

    /// Local reminder from Siri — tapping it opens compose for that person.
    static let thankReminderTypeKey = "type"
    static let thankReminderTypeValue = "thank_reminder"
    static let thankReminderNameKey = "recipientName"

    static func scheduleThankReminder(recipientName: String, fireDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Time to say thanks"
        content.body = "Thank \(recipientName) on OpenThanks"
        content.sound = .default
        content.userInfo = [
            thankReminderTypeKey: thankReminderTypeValue,
            thankReminderNameKey: recipientName,
        ]

        let interval = max(fireDate.timeIntervalSinceNow, 45)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let id = "thank-reminder-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    static func uploadDeviceToken(_ token: String, userId: UUID) async {
        let row = DevicePushToken(userId: userId, token: token, platform: "ios")
        do {
            try await supabase.from("device_push_tokens")
                .upsert(row, onConflict: "token", returning: .minimal)
                .execute()
        } catch {
            print("Couldn't save push token: \(error.localizedDescription)")
        }
    }
}
