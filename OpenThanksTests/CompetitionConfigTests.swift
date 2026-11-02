import XCTest
#if canImport(StreakMath)
@testable import StreakMath
#else
@testable import OpenThanks
#endif

final class CompetitionConfigTests: XCTestCase {
    private var eastern: TimeZone {
        TimeZone(identifier: "America/New_York")!
    }

    private var easternCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        return calendar
    }

    private func date(
        year: Int = 2026,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        easternCalendar.date(from: DateComponents(
            timeZone: eastern,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    /// Same strategy as `CompetitionConfigService`: internet date-time, then fractional seconds.
    private func competitionDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: raw) {
                return date
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date: \(raw)"
            )
        }
        return decoder
    }

    func testDecodesWithoutBodyOrProgressLabel() throws {
        let json = """
        {
          "id": "november-2026",
          "title": "30 Days of Thanks",
          "subtitle": "November 1–30, 2026",
          "prizeLabel": "$100 to your cause",
          "termsUrl": "https://openthanks.com/november",
          "targetDays": 30,
          "startsAt": null,
          "endsAt": null,
          "enabled": true,
          "rulesSummary": ["Send one thank-you every day"],
          "winnerNotifyBody": "You finished.",
          "allowedSources": [],
          "requireAccepted": false,
          "requireOtherRecipient": true
        }
        """.data(using: .utf8)!

        let config = try competitionDecoder().decode(CompetitionConfig.self, from: json)
        XCTAssertEqual(config.id, "november-2026")
        XCTAssertEqual(config.title, "30 Days of Thanks")
        XCTAssertEqual(config.targetDays, 30)
        XCTAssertNil(config.startsAt)
        XCTAssertNil(config.endsAt)
        XCTAssertNil(config.body)
        XCTAssertNil(config.progressLabel)
        XCTAssertEqual(config.rulesSummary, ["Send one thank-you every day"])
        XCTAssertTrue(config.isActive(at: date(month: 11, day: 2)))
    }

    func testDecodesBodyProgressLabelAndWindow() throws {
        let json = """
        {
          "id": "november-2026",
          "title": "30 Days of Thanks",
          "subtitle": "November 1–30, 2026",
          "prizeLabel": "$100 to your cause",
          "termsUrl": "https://openthanks.com/november",
          "targetDays": 30,
          "startsAt": "2026-11-01T04:00:00Z",
          "endsAt": "2026-12-01T05:00:00Z",
          "enabled": true,
          "rulesSummary": ["One line"],
          "winnerNotifyBody": "You finished.",
          "allowedSources": [],
          "requireAccepted": false,
          "requireOtherRecipient": true,
          "body": "Send every day in November.",
          "progressLabel": "November days with a thanks"
        }
        """.data(using: .utf8)!

        let config = try competitionDecoder().decode(CompetitionConfig.self, from: json)
        XCTAssertEqual(config.body, "Send every day in November.")
        XCTAssertEqual(config.progressLabel, "November days with a thanks")
        XCTAssertEqual(config.startsAt, date(month: 11, day: 1, hour: 0, minute: 0))
        XCTAssertEqual(config.endsAt, date(month: 12, day: 1, hour: 0, minute: 0))
    }

    func testDisabledDefaultHasNoCampaignCopy() {
        let config = CompetitionConfig.disabled
        let blob = [
            config.id,
            config.title,
            config.subtitle,
            config.prizeLabel,
            config.termsUrl,
            config.winnerNotifyBody,
            config.body ?? "",
            config.progressLabel ?? "",
            config.rulesSummary.joined(separator: "\n"),
        ].joined(separator: "\n")

        XCTAssertEqual(config.winnerNotifyBody, "")
        XCTAssertNil(config.body)
        XCTAssertNil(config.progressLabel)
        XCTAssertFalse(config.enabled)
        XCTAssertFalse(config.isActive())
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("november"))
        XCTAssertFalse(blob.contains("$100"))
        XCTAssertFalse(blob.contains("$30"))
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("classroom"))
        XCTAssertFalse(blob.localizedCaseInsensitiveContains("30 days"))
    }

    func testWindowedDayCountInEasternTime() {
        let start = date(month: 11, day: 1, hour: 0, minute: 0)
        let end = date(month: 12, day: 1, hour: 0, minute: 0)
        let nov1Morning = date(month: 11, day: 1, hour: 0, minute: 30)
        let nov1Evening = date(month: 11, day: 1, hour: 21)
        let nov15 = date(month: 11, day: 15)
        let nov30Late = date(month: 11, day: 30, hour: 23, minute: 59)
        let oct31 = date(month: 10, day: 31, hour: 23, minute: 59)
        let dec1 = date(month: 12, day: 1, hour: 0, minute: 0)

        XCTAssertEqual(
            StreakMath.distinctSendDays(dates: [], from: start, until: end, calendar: easternCalendar).count,
            0
        )
        XCTAssertEqual(
            StreakMath.distinctSendDays(
                dates: [oct31, dec1, date(year: 2025, month: 11, day: 15), date(year: 2027, month: 11, day: 15)],
                from: start,
                until: end,
                calendar: easternCalendar
            ).count,
            0
        )
        XCTAssertEqual(
            StreakMath.distinctSendDays(
                dates: [nov1Morning, nov1Evening, nov15, nov30Late, oct31, dec1],
                from: start,
                until: end,
                calendar: easternCalendar
            ).count,
            3
        )

        let everyDay = (1...30).map { date(month: 11, day: $0, hour: 9) }
        let extraSameDay = date(month: 11, day: 7, hour: 18)
        XCTAssertEqual(
            StreakMath.distinctSendDays(
                dates: everyDay + [extraSameDay],
                from: start,
                until: end,
                calendar: easternCalendar
            ).count,
            30
        )

        // 9:30 p.m. Pacific on Oct 31 is already November 1 in New York.
        var pacific = Calendar(identifier: .gregorian)
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        pacific.timeZone = losAngeles
        let stillOctoberOnThePacificCoast = pacific.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 10,
            day: 31,
            hour: 21,
            minute: 30
        ))!
        XCTAssertEqual(
            StreakMath.distinctSendDays(
                dates: [stillOctoberOnThePacificCoast],
                from: start,
                until: end,
                calendar: easternCalendar
            ).count,
            1
        )

        // 9:30 p.m. Pacific on Nov 30 is December 1 in New York, outside [start, end).
        let lastEveningPacific = pacific.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 11,
            day: 30,
            hour: 21,
            minute: 30
        ))!
        XCTAssertEqual(
            StreakMath.distinctSendDays(
                dates: [lastEveningPacific],
                from: start,
                until: end,
                calendar: easternCalendar
            ).count,
            0
        )
    }

    func testOctoberStreakDoesNotCarryIntoNovemberWindow() {
        let start = date(month: 11, day: 1, hour: 0, minute: 0)
        let end = date(month: 12, day: 1, hour: 0, minute: 0)
        let config = windowedConfig(startsAt: start, endsAt: end)

        let october = (1...31).map { date(month: 10, day: $0, hour: 9) }
        let before = posts(on: october)
        XCTAssertEqual(
            StreakMath.competitionProgressCount(
                posts: before,
                config: config,
                calendar: easternCalendar,
                now: date(month: 10, day: 31, hour: 18)
            ),
            0
        )
        XCTAssertEqual(
            StreakMath.competitionSentStreak(
                posts: before,
                config: config,
                calendar: easternCalendar,
                now: date(month: 10, day: 31, hour: 18)
            ),
            0
        )
        XCTAssertEqual(
            StreakMath.competitionCurrentStreak(
                posts: before,
                config: config,
                calendar: easternCalendar,
                now: date(month: 10, day: 31, hour: 18)
            ),
            0
        )
        XCTAssertEqual(
            StreakMath.competitionEligibleDayCount(
                posts: before,
                config: config,
                calendar: easternCalendar,
                now: date(month: 10, day: 31, hour: 18)
            ),
            0
        )

        // A daily streak from Oct 1 through Nov 10 counts only the 10 November days.
        let crossed = october + (1...10).map { date(month: 11, day: $0, hour: 9) }
        let now = date(month: 11, day: 10, hour: 18)
        let crossedPosts = posts(on: crossed)
        XCTAssertEqual(
            StreakMath.competitionProgressCount(
                posts: crossedPosts,
                config: config,
                calendar: easternCalendar,
                now: now
            ),
            10
        )
        XCTAssertEqual(
            StreakMath.competitionSentStreak(
                posts: crossedPosts,
                config: config,
                calendar: easternCalendar,
                now: now
            ),
            10
        )
        XCTAssertEqual(
            StreakMath.competitionCurrentStreak(
                posts: crossedPosts,
                config: config,
                calendar: easternCalendar,
                now: now
            ),
            10
        )
        XCTAssertEqual(
            StreakMath.competitionEligibleDayCount(
                posts: crossedPosts,
                config: config,
                calendar: easternCalendar,
                now: now
            ),
            10
        )

        // The day the window opens, only that day counts — not the October run.
        let throughOpening = posts(on: october + [date(month: 11, day: 1, hour: 9)])
        let opening = date(month: 11, day: 1, hour: 15)
        XCTAssertEqual(
            StreakMath.competitionSentStreak(
                posts: throughOpening,
                config: config,
                calendar: easternCalendar,
                now: opening
            ),
            1
        )
        XCTAssertEqual(
            StreakMath.competitionProgressCount(
                posts: throughOpening,
                config: config,
                calendar: easternCalendar,
                now: opening
            ),
            1
        )
    }

    func testRollingStreakWhenWindowIsUnset() {
        let config = windowedConfig(startsAt: nil, endsAt: nil)
        let dates = [
            date(month: 10, day: 30, hour: 9),
            date(month: 10, day: 31, hour: 9),
            date(month: 11, day: 1, hour: 9),
        ]
        XCTAssertEqual(
            StreakMath.competitionProgressCount(
                posts: posts(on: dates),
                config: config,
                calendar: easternCalendar,
                now: date(month: 11, day: 1, hour: 15)
            ),
            3
        )
    }

    private func windowedConfig(startsAt: Date?, endsAt: Date?) -> CompetitionConfig {
        CompetitionConfig(
            enabled: true,
            id: "november-2026",
            title: "30 Days of Thanks",
            subtitle: "November 1–30, 2026",
            prizeLabel: "$100 to your cause",
            targetDays: 30,
            startsAt: startsAt,
            endsAt: endsAt,
            allowedSources: [],
            requireAccepted: false,
            requireOtherRecipient: true,
            termsUrl: "https://openthanks.com/november",
            rulesSummary: [],
            winnerNotifyBody: "You finished."
        )
    }

    private func posts(on dates: [Date]) -> [SentActivity] {
        let author = UUID()
        let recipient = UUID()
        return dates.map { created in
            SentActivity(
                id: UUID(),
                createdAt: created,
                source: "ios",
                status: .accepted,
                recipientId: recipient,
                authorId: author
            )
        }
    }
}
