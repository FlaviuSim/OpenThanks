import XCTest
#if canImport(NovemberCampaign)
@testable import NovemberCampaign
#else
@testable import OpenThanks
#endif

final class NovemberCampaignCardTests: XCTestCase {
    private var eastern: TimeZone {
        TimeZone(identifier: "America/New_York")!
    }

    private func date(
        year: Int = 2026,
        month: Int,
        day: Int,
        hour: Int = 12,
        minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        return calendar.date(from: DateComponents(
            timeZone: eastern,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    func testCardCopyMatchesNovemberCampaign() {
        XCTAssertEqual(NovemberCampaignCard.title, "30 Days of Thanks")
        XCTAssertEqual(NovemberCampaignCard.subtitle, "November 1–30, 2026")
        XCTAssertEqual(NovemberCampaignCard.prizeLabel, "$100 to your cause")
        XCTAssertEqual(
            NovemberCampaignCard.body,
            "Send a real appreciation every day for all 30 days of November, with no missed days, and we'll donate $100 to your favorite cause."
        )
        XCTAssertEqual(
            NovemberCampaignCard.rules,
            [
                "Send one thank-you every day, Nov 1–30 (no missed days)",
                "First 100 finishers get a $100 donation to their favorite cause",
            ]
        )
        XCTAssertEqual(NovemberCampaignCard.progressLabel, "November days with a thanks")
        XCTAssertEqual(NovemberCampaignCard.targetDays, 30)
        XCTAssertEqual(NovemberCampaignCard.termsURL.absoluteString, "https://openthanks.com/november")
        XCTAssertEqual(NovemberCampaignCard.timeZoneID, "America/New_York")
        XCTAssertEqual(NovemberCampaignCard.progressValue(daysSent: 7), "7 of 30")
        XCTAssertEqual(NovemberCampaignCard.progressValue(daysSent: 0), "0 of 30")
        XCTAssertEqual(NovemberCampaignCard.progressValue(daysSent: 40), "30 of 30")

        let card = [
            NovemberCampaignCard.title,
            NovemberCampaignCard.subtitle,
            NovemberCampaignCard.prizeLabel,
            NovemberCampaignCard.body,
            NovemberCampaignCard.progressLabel,
            NovemberCampaignCard.winnerNotifyBody,
            NovemberCampaignCard.winnerVerb,
        ].joined(separator: "\n") + "\n" + NovemberCampaignCard.rules.joined(separator: "\n")
        XCTAssertFalse(NovemberCampaignCard.isRetiredChallengeCopy(card))
        XCTAssertFalse(card.contains("$30"))
        XCTAssertFalse(card.localizedCaseInsensitiveContains("classroom"))
    }

    func testRetiredChallengeCopy() {
        XCTAssertTrue(NovemberCampaignCard.isRetiredChallengeCopy(
            "Finishers unlock $30 to give away to a classroom."
        ))
        XCTAssertTrue(NovemberCampaignCard.isRetiredChallengeCopy("Classroom gift"))
        XCTAssertFalse(NovemberCampaignCard.isRetiredChallengeCopy(NovemberCampaignCard.body))
        XCTAssertFalse(NovemberCampaignCard.isRetiredChallengeCopy(NovemberCampaignCard.winnerNotifyBody))
    }

    func testNovemberDayCountIgnoresOutsideDaysAndDuplicates() {
        let nov1Morning = date(month: 11, day: 1, hour: 0, minute: 30)
        let nov1Evening = date(month: 11, day: 1, hour: 21)
        let nov15 = date(month: 11, day: 15)
        let nov30Late = date(month: 11, day: 30, hour: 23, minute: 59)
        let oct31 = date(month: 10, day: 31, hour: 23, minute: 59)
        let dec1 = date(month: 12, day: 1, hour: 0, minute: 0)
        let nov2025 = date(year: 2025, month: 11, day: 15)
        let nov2027 = date(year: 2027, month: 11, day: 15)

        XCTAssertEqual(NovemberCampaignCard.sendDayCount(dates: []), 0)
        XCTAssertEqual(NovemberCampaignCard.sendDayCount(dates: [oct31, dec1, nov2025, nov2027]), 0)
        XCTAssertEqual(
            NovemberCampaignCard.sendDayCount(dates: [nov1Morning, nov1Evening, nov15, nov30Late, oct31, dec1]),
            3
        )
        XCTAssertEqual(NovemberCampaignCard.progressValue(daysSent: 3), "3 of 30")
    }

    func testEveryNovemberDayCountsOnce() {
        let dates = (1...30).map { date(month: 11, day: $0, hour: 9) }
        let extraSameDay = date(month: 11, day: 7, hour: 18)
        XCTAssertEqual(NovemberCampaignCard.sendDayCount(dates: dates + [extraSameDay]), 30)
        XCTAssertEqual(NovemberCampaignCard.progressValue(daysSent: 30), "30 of 30")
    }

    func testEasternBoundaryNotLocalOffset() {
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
        XCTAssertEqual(NovemberCampaignCard.sendDayCount(dates: [stillOctoberOnThePacificCoast]), 1)

        // 9:30 p.m. Pacific on Nov 30 is December 1 in New York.
        let lastEveningPacific = pacific.date(from: DateComponents(
            timeZone: losAngeles,
            year: 2026,
            month: 11,
            day: 30,
            hour: 21,
            minute: 30
        ))!
        XCTAssertEqual(NovemberCampaignCard.sendDayCount(dates: [lastEveningPacific]), 0)
    }
}
