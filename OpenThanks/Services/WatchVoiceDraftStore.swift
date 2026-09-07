import Foundation
import UIKit
import UserNotifications

/// Holds a polished Watch voice draft until the user finishes it in Compose.
enum WatchVoiceDraftStore {
    private static let defaultsKey = "openthanks.watchVoiceDraft.v1"
    static let notificationTypeValue = "watch_voice_draft"
    private static let notificationId = "watch-voice-draft"

    struct Draft: Codable, Equatable {
        var id: UUID
        var message: String
        var createdAt: Date
    }

    static func save(_ draft: Draft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load() -> Draft? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data)
        else { return nil }
        let trimmed = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return nil
        }
        return draft
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    /// Queue compose + optional banner when the phone isn't foregrounded.
    @MainActor
    static func presentForReview(message: String, draftId: UUID) {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let draft = Draft(id: draftId, message: cleaned, createdAt: .now)
        save(draft)

        ComposeLaunchBridge.shared.queue(
            message: cleaned,
            analyticsSource: "watch",
            allowsEmptyRecipient: true
        )

        Task {
            await notifyIfNeeded(draftId: draftId)
        }
    }

    /// Cold start / resume: re-queue a draft that wasn't finished.
    @MainActor
    static func restorePendingComposeIfNeeded() {
        guard let draft = load() else { return }
        if let pending = ComposeLaunchBridge.shared.pending,
           pending.analyticsSource == "watch" {
            return
        }
        ComposeLaunchBridge.shared.queue(
            message: draft.message,
            analyticsSource: "watch",
            allowsEmptyRecipient: true
        )
    }

    private static func notifyIfNeeded(draftId: UUID) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        if await MainActor.run(body: { UIApplication.shared.applicationState == .active }) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Finish your Watch thanks"
        content.body = "We polished your recording — review and save it in OpenThanks."
        content.sound = .default
        content.userInfo = [
            NotificationService.thankReminderTypeKey: notificationTypeValue,
            "draftId": draftId.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
