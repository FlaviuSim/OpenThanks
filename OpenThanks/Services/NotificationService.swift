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
