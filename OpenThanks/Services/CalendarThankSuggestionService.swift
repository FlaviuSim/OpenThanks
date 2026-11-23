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
               let suggestion = server.suggestion {
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
        Task { await CalendarServerAPI.consumeSuggestion(id: suggestion.id) }
        Analytics.calendarAIThankOpened()
    }
}
