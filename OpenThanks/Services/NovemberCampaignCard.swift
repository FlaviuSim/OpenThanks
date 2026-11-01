import Foundation

/// Profile → Your Stats copy for the live November 2026 campaign.
///
/// The campaign feed title is "30 Days of Thanks: Who Shaped You?".
/// That line does not fit beside the amount in the existing stats header,
/// so the card keeps the short label already used by `CampaignFeed.cardTitle`.
/// Terms match `https://openthanks.com/november`.
enum NovemberCampaignCard {
    static let title = "30 Days of Thanks"
    static let subtitle = "November 1–30, 2026"
    static let prizeLabel = "$100 to your cause"
    static let body = "Send a real appreciation every day for all 30 days of November, with no missed days, and we'll donate $100 to your favorite cause."
    static let rules: [String] = [
        "Send one thank-you every day, Nov 1–30 (no missed days)",
        "First 100 finishers get a $100 donation to their favorite cause",
    ]
    static let progressLabel = "November days with a thanks"
    static let targetDays = 30
    static let termsURL = URL(string: "https://openthanks.com/november")!
    /// Matches `CampaignFeed.fallbackTimeZoneID` and the campaign JSON.
    static let timeZoneID = "America/New_York"
    /// Shown when a finisher notification has no newer remote copy.
    static let winnerNotifyBody = "You finished 30 Days of Thanks. The first 100 finishers get a $100 donation to their favorite cause."
    static let winnerVerb = "🏆 \(winnerNotifyBody)"

    static func progressValue(daysSent: Int) -> String {
        "\(capped(daysSent)) of \(targetDays)"
    }

    static func capped(_ daysSent: Int) -> Int {
        min(max(daysSent, 0), targetDays)
    }

    /// The retired rolling challenge ($30 to a classroom). Remote `app_config`
    /// may still say this; the stats card and finisher fallback do not show it.
    static func isRetiredChallengeCopy(_ text: String) -> Bool {
        let folded = text.lowercased()
        return folded.contains("$30") || folded.contains("classroom")
    }

    /// Distinct Eastern November 2026 days with at least one send.
    /// Uses the same inclusive start-of-day window as `StreakMath.distinctSendDays`.
    static func sendDayCount(dates: [Date], timeZone: TimeZone? = nil) -> Int {
        let zone = timeZone ?? TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: -5 * 3600)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard
            let start = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 11, day: 1)),
            let end = calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 11, day: 30))
        else { return 0 }
        return capped(distinctSendDays(dates: dates, from: start, through: end, calendar: calendar).count)
    }

    static func distinctSendDays(
        dates: [Date],
        from start: Date,
        through end: Date,
        calendar: Calendar
    ) -> Set<Date> {
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        var days = Set<Date>()
        for date in dates {
            let day = calendar.startOfDay(for: date)
            if day >= first && day <= last {
                days.insert(day)
            }
        }
        return days
    }
}
