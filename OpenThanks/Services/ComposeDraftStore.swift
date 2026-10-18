import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Unsent compose text, kept on device. One local reminder per draft.
enum ComposeDraftStore {
    static let storageKey = "openthanks.composeDraft.v1"
    static let notificationID = "compose-draft-reminder"
    static let typeValue = "compose_draft"
    static let reminderDelay: TimeInterval = 24 * 60 * 60

    struct Draft: Codable, Equatable {
        var recipient: String
        var message: String
        var reminderScheduled: Bool
    }

    struct FormContext: Equatable {
        var isEditing = false
        var analyticsSource = ""
        var hasInitialRecipient = false
        var hasInitialProfile = false
        var hasInitialMessage = false
        var hasInitialImage = false
        var hasInspiredBy = false
        var hasCampaign = false
    }

    struct LeaveEffect: Equatable {
        var saved: Bool
        var scheduled: Bool
        var discarded: Bool
        var hasRecipient: Bool
    }

    protocol Scheduling: AnyObject {
        func permissionGranted() async -> Bool
        func schedule(id: String, title: String, after: TimeInterval) async -> Bool
        func cancel(id: String)
    }

    static var defaults: UserDefaults = .standard
    static var scheduler: Scheduling = SystemScheduler()

    /// Blank send form (heart tab, draft reminder). Campaign, Watch, and
    /// explicit prefills keep their own launch and do not touch this draft.
    static func ownsDraft(_ form: FormContext) -> Bool {
        if form.isEditing || form.analyticsSource == "watch" { return false }
        if form.analyticsSource.hasPrefix("campaign") { return false }
        if form.hasInitialRecipient || form.hasInitialProfile || form.hasInitialMessage { return false }
        if form.hasInitialImage || form.hasInspiredBy || form.hasCampaign { return false }
        return true
    }

    static func reminderTitle(recipient: String) -> String {
        let name = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Finish your thank-you?" }
        return "Finish your thank-you to \(name)?"
    }

    static func restore() -> Draft? {
        guard let data = defaults.data(forKey: storageKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data)
        else { return nil }
        let recipient = draft.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty || !message.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return nil
        }
        return draft
    }

    static func clearAfterSend() { remove() }
    static func discard() { remove() }

    static func leave(recipient: String, message: String) async -> LeaveEffect {
        let recipient = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty || !message.isEmpty else {
            let had = restore() != nil
            if had { discard() }
            return LeaveEffect(saved: false, scheduled: false, discarded: had, hasRecipient: false)
        }

        let existing = restore()
        var reminderOn = existing?.reminderScheduled == true
        var scheduled = false
        if !reminderOn, await scheduler.permissionGranted() {
            scheduled = await scheduler.schedule(
                id: notificationID,
                title: reminderTitle(recipient: recipient),
                after: reminderDelay
            )
            reminderOn = scheduled
        }
        let draft = Draft(recipient: recipient, message: message, reminderScheduled: reminderOn)
        if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: storageKey)
        }
        return LeaveEffect(
            saved: true,
            scheduled: scheduled,
            discarded: false,
            hasRecipient: !recipient.isEmpty
        )
    }

    private static func remove() {
        defaults.removeObject(forKey: storageKey)
        scheduler.cancel(id: notificationID)
    }

    final class SystemScheduler: Scheduling {
        func permissionGranted() async -> Bool {
            #if canImport(UserNotifications)
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            switch status {
            case .authorized, .provisional, .ephemeral: return true
            default: return false
            }
            #else
            return false
            #endif
        }

        func schedule(id: String, title: String, after: TimeInterval) async -> Bool {
            #if canImport(UserNotifications)
            let content = UNMutableNotificationContent()
            content.title = title
            content.sound = .default
            content.userInfo = ["type": ComposeDraftStore.typeValue]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(after, 1),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(request)
                return true
            } catch {
                return false
            }
            #else
            return false
            #endif
        }

        func cancel(id: String) {
            #if canImport(UserNotifications)
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [id])
            center.removeDeliveredNotifications(withIdentifiers: [id])
            #endif
        }
    }
}
