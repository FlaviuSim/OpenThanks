import Foundation

/// Prefers server AI suggestions; falls back to on-device today-only ranking while backfilling.
enum CalendarThankSuggestionService {
    /// Best available nudge for scheduling / Home.
    static func resolveNudge(
        for day: Date = Date(),
        authorId: UUID?,
        selfEmails: Set<String> = [],
        now: Date = Date()
    ) async -> GratitudeNudge? {
        if CalendarServerSyncConsent.hasConsented {
            if let server = try? await CalendarServerAPI.todaySuggestion(),
               let suggestion = CalendarSuggestionSuppressStore.visibleSuggestion(server.suggestion) {
                Analytics.calendarAISuggested(source: suggestion.source ?? "server")
                return CalendarServerAPI.asNudge(suggestion, day: day)
            }
            // While backfilling, keep on-device today-only fallback.
        }

        return await GratitudeOpportunityRanker.pickNudge(
            for: day,
            authorId: authorId,
            selfEmails: selfEmails,
            now: now
        )
    }

    @MainActor
    static func openCompose(from suggestion: CalendarServerAPI.Suggestion) {
        let recipient = suggestion.person_email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = suggestion.person_name.trimmingCharacters(in: .whitespacesAndNewlines)
        ComposeLaunchBridge.shared.queue(
            recipientName: (recipient?.isEmpty == false) ? recipient : name,
            message: suggestion.draft,
            analyticsSource: "calendar_ai_suggestion"
        )
        CalendarSuggestionSuppressStore.suppress(suggestion)
        Task { await CalendarServerAPI.consumeSuggestion(id: suggestion.id) }
        Analytics.calendarAIThankOpened()
    }

    /// Home X — hide for today / cooldown and mark consumed so reloads don't resurrect them.
    @MainActor
    static func dismiss(_ suggestion: CalendarServerAPI.Suggestion) {
        CalendarSuggestionSuppressStore.suppress(suggestion)
        CalendarThankSuggestionStore.remove(on: Date())
        Task { await CalendarServerAPI.consumeSuggestion(id: suggestion.id) }
        Analytics.capture("calendar_ai_suggestion_dismissed", [
            "for_day": suggestion.for_day,
            "source": suggestion.source ?? "server",
        ])
    }
}
