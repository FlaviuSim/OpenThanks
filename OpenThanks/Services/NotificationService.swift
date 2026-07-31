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
        let environment: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case token
            case platform
            case environment
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

    /// Why enabling a Settings notification toggle failed (nil = success).
    enum ReminderEnableFailure: Equatable {
        case notificationsDenied
        case calendarDenied
        case schedulingFailed
    }

    static func enableFridayReminder() async -> ReminderEnableFailure? {
        guard await requestAuthorizationAndRegisterForPushes() else {
            return .notificationsDenied
        }

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
            return nil
        } catch {
            return .schedulingFailed
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
    /// Returns nil on success. Preference can stay on even when there’s no candidate tonight.
    static func enableCalendarGratitudeNudge(
        authorId: UUID?,
        selfEmails: Set<String>
    ) async -> ReminderEnableFailure? {
        guard await requestAuthorizationAndRegisterForPushes() else {
            return .notificationsDenied
        }
        // Don't re-prompt when the system already denied — Settings must flip it.
        switch CalendarMeetingService.accessState {
        case .fullAccess:
            break
        case .notDetermined:
            guard await CalendarMeetingService.requestAccess() else {
                return .calendarDenied
            }
        case .denied, .restricted, .writeOnly:
            return .calendarDenied
        }
        await refreshCalendarGratitudeNudgeIfEnabled(
            true,
            authorId: authorId,
            selfEmails: selfEmails
        )
        return nil
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
        // DEBUG → APNs sandbox; Release / TestFlight / App Store → production.
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let row = DevicePushToken(
            userId: userId,
            token: token,
            platform: "ios",
            environment: environment
        )
        do {
            try await supabase.from("device_push_tokens")
                .upsert(row, onConflict: "token", returning: .minimal)
                .execute()
        } catch {
            print("Couldn't save push token: \(error.localizedDescription)")
        }
    }
}
