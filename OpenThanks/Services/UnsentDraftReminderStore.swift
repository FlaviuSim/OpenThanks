import Foundation
import UserNotifications

/// Local reminders for pending appreciations that still have no recipient and
/// have not been shared via Copy Link / Text / WhatsApp / Email / system Share.
///
/// Complements `WatchVoiceDraftStore`'s immediate Watch handoff nudge with a
/// longer follow-up for any no-recipient draft (including Watch after review).
enum UnsentDraftReminderStore {
    static let notificationTypeValue = "unsent_draft_reminder"
    static let gratitudeIdKey = "gratitudeId"

    private static let recordsKey = "openthanks.unsentDraftReminders.v1"
    private static let sharedIdsKey = "openthanks.unsentDraftShared.v1"

    private static let firstDelay: TimeInterval = 4 * 60 * 60
    private static let maxReminders = 2

    struct Record: Codable, Equatable {
        var gratitudeId: UUID
        var createdAt: Date
        /// How many local reminders have been scheduled for this draft.
        var reminderCount: Int
        /// When the next (or last scheduled) reminder should fire.
        var nextFireAt: Date?
    }

    // MARK: - Share tracking

    static func hasShared(id: UUID) -> Bool {
        sharedIds().contains(id.uuidString.lowercased())
    }

    static func markShared(id: UUID) {
        var ids = sharedIds()
        ids.insert(id.uuidString.lowercased())
        UserDefaults.standard.set(Array(ids), forKey: sharedIdsKey)
        clear(id: id)
    }

    private static func sharedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: sharedIdsKey) ?? [])
    }

    // MARK: - Records

    static func loadRecords() -> [Record] {
        guard let data = UserDefaults.standard.data(forKey: recordsKey),
              let decoded = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        return decoded
    }

    private static func saveRecords(_ records: [Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: recordsKey)
    }

    static func clear(id: UUID) {
        var records = loadRecords()
        records.removeAll { $0.gratitudeId == id }
        saveRecords(records)
        let notifId = notificationId(for: id)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notifId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notifId])
    }

    /// Call when a recipient is saved on the deliver screen.
    static func markRecipientAdded(id: UUID) {
        clear(id: id)
    }

    private static func notificationId(for id: UUID) -> String {
        "unsent-draft-\(id.uuidString.lowercased())"
    }

    // MARK: - Schedule

    /// Register / refresh a reminder if the draft is still eligible.
    @MainActor
    static func scheduleIfNeeded(for gratitude: Gratitude) async {
        guard gratitude.hasNoRecipient else {
            clear(id: gratitude.id)
            return
        }
        guard !hasShared(id: gratitude.id) else {
            clear(id: gratitude.id)
            return
        }
        guard gratitude.status == .pending || gratitude.status == nil else {
            clear(id: gratitude.id)
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            // Still track locally so we can schedule once permission is granted.
            upsertRecord(gratitudeId: gratitude.id, scheduleNotification: false)
            return
        }

        upsertRecord(gratitudeId: gratitude.id, scheduleNotification: true)
    }

    private static func upsertRecord(gratitudeId: UUID, scheduleNotification: Bool) {
        var records = loadRecords()
        let now = Date()
        if let index = records.firstIndex(where: { $0.gratitudeId == gratitudeId }) {
            var existing = records[index]
            if existing.reminderCount >= maxReminders {
                return
            }
            // Keep an already-pending fire time; only schedule if none is pending.
            if existing.nextFireAt == nil || (existing.nextFireAt ?? .distantPast) <= now {
                let fire = nextFireDate(afterCount: existing.reminderCount, from: now)
                existing.nextFireAt = fire
                existing.reminderCount += 1
                records[index] = existing
                saveRecords(records)
                if scheduleNotification {
                    enqueueLocalNotification(gratitudeId: gratitudeId, fireAt: fire, count: existing.reminderCount)
                }
            }
            return
        }

        let fire = nextFireDate(afterCount: 0, from: now)
        let record = Record(
            gratitudeId: gratitudeId,
            createdAt: now,
            reminderCount: scheduleNotification ? 1 : 0,
            nextFireAt: scheduleNotification ? fire : nil
        )
        records.append(record)
        saveRecords(records)
        if scheduleNotification {
            enqueueLocalNotification(gratitudeId: gratitudeId, fireAt: fire, count: 1)
        }
    }

    /// First reminder ~4h later; second at 10:00 local the following calendar day.
    private static func nextFireDate(afterCount: Int, from now: Date) -> Date {
        if afterCount <= 0 {
            return now.addingTimeInterval(firstDelay)
        }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(24 * 60 * 60)
        return cal.date(bySettingHour: 10, minute: 0, second: 0, of: tomorrow)
            ?? tomorrow.addingTimeInterval(10 * 60 * 60)
    }

    private static func enqueueLocalNotification(gratitudeId: UUID, fireAt: Date, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Finish sending your appreciation"
        content.body = count == 1
            ? "Your note is saved — add who it’s for, or share the link when you’re ready."
            : "Still in Pending — add a recipient or share the link so they can accept."
        content.sound = .default
        content.userInfo = [
            NotificationService.thankReminderTypeKey: notificationTypeValue,
            gratitudeIdKey: gratitudeId.uuidString,
        ]

        let interval = max(fireAt.timeIntervalSinceNow, 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: notificationId(for: gratitudeId),
            content: content,
            trigger: trigger
        )
        // Replace any prior pending request for this draft.
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId(for: gratitudeId)])
        Task {
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Reconcile / open

    /// Drop reminders for drafts that are gone, accepted, have a recipient, or were shared.
    @MainActor
    static func reconcile(pending: [Gratitude]) async {
        let pendingById = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, $0) })
        let records = loadRecords()
        for record in records {
            guard let gratitude = pendingById[record.gratitudeId] else {
                clear(id: record.gratitudeId)
                continue
            }
            if !gratitude.hasNoRecipient || hasShared(id: gratitude.id) {
                clear(id: gratitude.id)
                continue
            }
            // If a fire time passed without us clearing, schedule the follow-up.
            if let next = record.nextFireAt, next <= Date(), record.reminderCount < maxReminders {
                await scheduleIfNeeded(for: gratitude)
            }
        }

        // Ensure every eligible pending draft is tracked (e.g. created on another device).
        for gratitude in pending where gratitude.hasNoRecipient && !hasShared(id: gratitude.id) {
            if !loadRecords().contains(where: { $0.gratitudeId == gratitude.id }) {
                await scheduleIfNeeded(for: gratitude)
            }
        }
    }

    /// Queue compose on the deliver screen for a reminder tap.
    @MainActor
    static func openDeliver(gratitudeId: UUID) async {
        guard let gratitude = try? await GratitudeService.gratitude(id: gratitudeId) else { return }
        ComposeLaunchBridge.shared.queue(
            analyticsSource: gratitude.hasNoRecipient ? "notification_unsent_draft" : "edit_own",
            allowsEmptyRecipient: gratitude.hasNoRecipient,
            editingGratitude: gratitude,
            opensOnShareScreen: true
        )
    }
}
