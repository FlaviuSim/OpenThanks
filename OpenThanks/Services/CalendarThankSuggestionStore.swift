import Foundation

/// On-device inbox rows for calendar “someone to thank” nudges.
/// Calendar PII stays local — never uploaded to Supabase `notifications`.
struct CalendarThankSuggestion: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// Start of the calendar day this nudge belongs to (dedupe key).
    let dayStart: Date
    let personName: String
    let email: String?
    let meetingTitle: String
    let messageDraft: String?
    let eventId: String
    let createdAt: Date
    var read: Bool
}

enum CalendarThankSuggestionStore {
    private static let key = "calendarThankSuggestions.v1"
    private static let maxItems = 40

    /// Saves / replaces today’s suggestion when an evening nudge is scheduled (or previewed).
    @discardableResult
    static func upsert(from nudge: GratitudeNudge, at now: Date = Date()) -> CalendarThankSuggestion {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: nudge.day)
        var items = load()
        let existingId = items.first(where: { cal.isDate($0.dayStart, inSameDayAs: dayStart) })?.id
        let suggestion = CalendarThankSuggestion(
            id: existingId ?? UUID(),
            dayStart: dayStart,
            personName: nudge.personName,
            email: nudge.email,
            meetingTitle: nudge.meetingTitle,
            messageDraft: nudge.messageDraft,
            eventId: nudge.eventId,
            createdAt: now,
            read: false
        )
        items.removeAll { cal.isDate($0.dayStart, inSameDayAs: dayStart) }
        items.insert(suggestion, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        save(items)
        return suggestion
    }

    static func all() -> [CalendarThankSuggestion] {
        load().sorted { $0.createdAt > $1.createdAt }
    }

    static func suggestion(id: UUID) -> CalendarThankSuggestion? {
        load().first { $0.id == id }
    }

    static func unreadCount() -> Int {
        load().filter { !$0.read }.count
    }

    static func markRead(id: UUID) {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }), !items[idx].read else { return }
        items[idx].read = true
        save(items)
    }

    static func markAllRead() {
        var items = load()
        var changed = false
        for i in items.indices where !items[i].read {
            items[i].read = true
            changed = true
        }
        if changed { save(items) }
    }

    /// Synthetic inbox rows merged into NotificationsView (same shape as remote notes).
    static func asAppNotifications(userId: UUID) -> [AppNotification] {
        all().map { item in
            AppNotification(
                id: item.id,
                userId: userId,
                type: NotificationService.calendarNudgeTypeValue,
                gratitudeId: nil,
                fromUserId: nil,
                read: item.read,
                createdAt: item.createdAt,
                fromUser: nil
            )
        }
    }

    /// Prefill for compose — prefer calendar email in To.
    static func composeRecipient(for item: CalendarThankSuggestion) -> String? {
        let email = item.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let email, !email.isEmpty { return email }
        let name = item.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private static func load() -> [CalendarThankSuggestion] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([CalendarThankSuggestion].self, from: data)) ?? []
    }

    private static func save(_ items: [CalendarThankSuggestion]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}
