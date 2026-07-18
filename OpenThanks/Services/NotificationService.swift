import Foundation
import UIKit
import UserNotifications
import Supabase

enum NotificationService {
    private static let fridayReminderId = "friday-gratitude-reminder"

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

    static func enableFridayReminder() async -> Bool {
        guard await requestAuthorizationAndRegisterForPushes() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "What are you grateful for?"
        content.body = "Take a minute to appreciate someone who made this week better."
        content.sound = .default

        var date = DateComponents()
        date.weekday = 6
        date.hour = 9
        date.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
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

    static func disableFridayReminder() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [fridayReminderId])
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
