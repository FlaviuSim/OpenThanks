import Foundation
import UserNotifications

/// One unsent compose draft on this device (recipient + message only).
///
/// Leaving the send form with text saves it. The next blank form restores it.
/// A prefilled launch (profile, calendar, Siri, campaign, share, edit) keeps its
/// own fields so existing entry points stay the same. Older builds ignore this
/// key and this notification type.
enum ComposeDraftStore {
    private static let defaultsKey = "openthanks.composeDraft.v1"
    static let notificationTypeValue = "compose_draft_reminder"
    private static let draftIdKey = "draftId"
    /// About a day after the draft is first saved with a recipient.
    static let reminderDelay: TimeInterval = 24 * 60 * 60
    private static let maxMessageLength = 1500
    private static let lock = NSLock()
    /// Bumped on discard/replace so an in-flight schedule cannot publish a stale reminder.
    private static var scheduleToken = 0
    private static var schedulingDraftId: UUID?

    struct Draft: Codable, Equatable {
        var id: UUID
        var recipient: String
        var message: String
        /// True after the one local reminder for this draft has been accepted by the system.
        var reminderScheduled: Bool
    }

    static func load() -> Draft? {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    static func matches(recipient: String, message: String) -> Bool {
        guard let draft = load() else { return false }
        return draft.recipient == normalize(recipient) && draft.message == normalizeMessage(message)
    }

    /// Updates the single draft. Schedules the 24h reminder at most once, and only
    /// when notification permission is already granted — never prompts.
    static func save(recipient: String, message: String) {
        let recipient = normalize(recipient)
        let message = normalizeMessage(message)
        guard !recipient.isEmpty || !message.isEmpty else { return }

        var replacedId: UUID?
        var shouldSchedule = false
        var scheduledDraftId = UUID()
        var token = 0

        lock.lock()
        let existing = read()
        let draft: Draft
        if let existing, existing.recipient == recipient {
            draft = Draft(
                id: existing.id,
                recipient: recipient,
                message: message,
                reminderScheduled: existing.reminderScheduled
            )
        } else {
            replacedId = existing?.id
            draft = Draft(
                id: UUID(),
                recipient: recipient,
                message: message,
                reminderScheduled: false
            )
            scheduleToken &+= 1
            schedulingDraftId = nil
        }
        let changed = existing != draft
        if !draft.reminderScheduled, !draft.recipient.isEmpty, schedulingDraftId != draft.id {
            shouldSchedule = true
            schedulingDraftId = draft.id
            scheduleToken &+= 1
            scheduledDraftId = draft.id
            token = scheduleToken
        }
        write(draft)
        lock.unlock()

        if let replacedId {
            cancelNotification(for: replacedId)
        }
        if changed {
            Analytics.draftSaved()
        }
        guard shouldSchedule else { return }
        let draftId = scheduledDraftId
        let generation = token
        Task.detached {
            await scheduleReminder(draftId: draftId, token: generation)
        }
    }

    /// Sent or cleared. Removes the draft and its pending or delivered reminder.
    static func discard() {
        lock.lock()
        let existing = read()
        scheduleToken &+= 1
        schedulingDraftId = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        lock.unlock()
        if let existing {
            cancelNotification(for: existing.id)
        }
    }

    static func reminderBody(recipient: String) -> String? {
        let name = recipient
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !name.isEmpty else { return nil }
        let shown: String
        if name.count > 80 {
            let end = name.index(name.startIndex, offsetBy: 79)
            shown = name[..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        } else {
            shown = name
        }
        return "Finish your thank-you to \(shown)?"
    }

    static func notificationIdentifier(for draftId: UUID) -> String {
        "compose-draft-reminder-\(draftId.uuidString.lowercased())"
    }

    // MARK: - Private

    private static func scheduleReminder(draftId: UUID, token: Int) async {
        let authorized = await NotificationService.isAuthorized()
        guard authorized else {
            clearSchedulingFlag(draftId: draftId, token: token)
            return
        }

        lock.lock()
        guard scheduleToken == token,
              let draft = read(),
              draft.id == draftId,
              !draft.reminderScheduled
        else {
            if scheduleToken == token, schedulingDraftId == draftId {
                schedulingDraftId = nil
            }
            lock.unlock()
            return
        }
        let body = reminderBody(recipient: draft.recipient)
        lock.unlock()

        guard let body else {
            clearSchedulingFlag(draftId: draftId, token: token)
            return
        }

        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = .default
        // No compose category — Watch uses that category to start recording.
        content.userInfo = [
            NotificationService.thankReminderTypeKey: notificationTypeValue,
            draftIdKey: draftId.uuidString,
        ]
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: reminderDelay,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: notificationIdentifier(for: draftId),
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            clearSchedulingFlag(draftId: draftId, token: token)
            return
        }

        var didSchedule = false
        lock.lock()
        if scheduleToken == token,
           var latest = read(),
           latest.id == draftId,
           !latest.reminderScheduled {
            latest.reminderScheduled = true
            write(latest)
            schedulingDraftId = nil
            didSchedule = true
        } else if scheduleToken == token, schedulingDraftId == draftId {
            schedulingDraftId = nil
        }
        lock.unlock()

        if didSchedule {
            await MainActor.run { Analytics.draftReminderScheduled() }
        } else {
            // This draft was sent, cleared, or replaced while the request was added.
            cancelNotification(for: draftId)
        }
    }

    private static func clearSchedulingFlag(draftId: UUID, token: Int) {
        lock.lock()
        if scheduleToken == token, schedulingDraftId == draftId {
            schedulingDraftId = nil
        }
        lock.unlock()
    }

    private static func cancelNotification(for draftId: UUID) {
        let center = UNUserNotificationCenter.current()
        let identifier = notificationIdentifier(for: draftId)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private static func read() -> Draft? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data)
        else { return nil }
        if draft.recipient.isEmpty && draft.message.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return nil
        }
        return draft
    }

    private static func write(_ draft: Draft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMessage(_ value: String) -> String {
        String(normalize(value).prefix(maxMessageLength))
    }
}
