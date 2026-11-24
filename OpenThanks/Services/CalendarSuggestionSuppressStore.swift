import Foundation

/// Durable Home / nudge suppress list for calendar AI suggestions.
/// Ephemeral `@State` dismiss was remounting and showing the same person again.
enum CalendarSuggestionSuppressStore {
    private static let key = "calendarSuggestion.suppress.v1"
    private static let maxEntries = 80

    struct Entry: Codable, Equatable, Sendable {
        let suggestionId: UUID
        let personKey: String
        let forDay: String
        /// Keep person hidden through this instant (end of local day + cooldown).
        let until: Date
    }

    /// Hide this suggestion for the rest of today and soft-cooldown the person (~7 days).
    static func suppress(_ suggestion: CalendarServerAPI.Suggestion, now: Date = Date()) {
        let cal = Calendar.current
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? now
        let cooldown = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now)) ?? now
        let until = max(endOfDay, cooldown)
        var items = load().filter { $0.until > now }
        items.removeAll {
            $0.suggestionId == suggestion.id
                || ($0.personKey == suggestion.person_key && $0.forDay == suggestion.for_day)
        }
        items.insert(
            Entry(
                suggestionId: suggestion.id,
                personKey: suggestion.person_key,
                forDay: suggestion.for_day,
                until: until
            ),
            at: 0
        )
        if items.count > maxEntries {
            items = Array(items.prefix(maxEntries))
        }
        save(items)
    }

    static func isSuppressed(_ suggestion: CalendarServerAPI.Suggestion, now: Date = Date()) -> Bool {
        if suggestion.consumed_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }
        return load().contains { entry in
            guard entry.until > now else { return false }
            if entry.suggestionId == suggestion.id { return true }
            // Same person stays hidden through the cooldown window.
            return entry.personKey == suggestion.person_key
        }
    }

    /// Visible suggestion for Home / resolveNudge, or nil when consumed / dismissed.
    static func visibleSuggestion(
        _ suggestion: CalendarServerAPI.Suggestion?,
        now: Date = Date()
    ) -> CalendarServerAPI.Suggestion? {
        guard let suggestion else { return nil }
        guard !isSuppressed(suggestion, now: now) else { return nil }
        return suggestion
    }

    private static func load() -> [Entry] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private static func save(_ items: [Entry]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        AppGroup.defaults.set(data, forKey: key)
    }
}
