import XCTest
#if canImport(ThanksgivingWindow)
@testable import ThanksgivingWindow
#else
@testable import OpenThanks
#endif

final class ThanksgivingWindowTests: XCTestCase {
    private func calendar(_ timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func date(
        _ calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        ))!
    }

    /// Monday before Thanksgiving, and the Sunday after, for years whose
    /// fourth Thursday of November was checked against the civil calendar.
    private let windows: [(year: Int, monday: (Int, Int), sunday: (Int, Int))] = [
        (2024, (11, 25), (12, 1)),
        (2025, (11, 24), (11, 30)),
        (2026, (11, 23), (11, 29)),
        (2027, (11, 22), (11, 28)),
        (2028, (11, 20), (11, 26)),
        (2029, (11, 19), (11, 25)),
        (2030, (11, 25), (12, 1)),
        (2031, (11, 24), (11, 30)),
        (2032, (11, 22), (11, 28)),
    ]

    func testKnownThanksgivingDates() {
        let newYork = calendar("America/New_York")
        let expectedDay = [
            2024: 28, 2025: 27, 2026: 26, 2027: 25, 2028: 23,
            2029: 22, 2030: 28, 2031: 27, 2032: 25,
        ]
        for (year, day) in expectedDay {
            let thanksgiving = ThanksgivingWindow.thanksgiving(year: year, timeZone: newYork.timeZone)
            let parts = newYork.dateComponents([.year, .month, .day, .weekday], from: thanksgiving!)
            XCTAssertEqual(parts.year, year, "year \(year)")
            XCTAssertEqual(parts.month, 11, "year \(year)")
            XCTAssertEqual(parts.day, day, "year \(year)")
            XCTAssertEqual(parts.weekday, 5, "Thursday year \(year)")
        }
    }

    func testBoundariesForSeveralYears() {
        let zones = ["America/New_York", "America/Los_Angeles", "UTC", "Pacific/Honolulu"]
        for zone in zones {
            let calendar = calendar(zone)
            for window in windows {
                let monday = date(calendar, year: window.year, month: window.monday.0, day: window.monday.1)
                let sundayBefore = date(
                    calendar,
                    year: window.year,
                    month: window.monday.0,
                    day: window.monday.1
                ).addingTimeInterval(-1)
                let sundayLate = date(
                    calendar,
                    year: window.year,
                    month: window.sunday.0,
                    day: window.sunday.1,
                    hour: 23,
                    minute: 59,
                    second: 59
                )
                let nextMonday = sundayLate.addingTimeInterval(1)
                let span = ThanksgivingWindow.span(year: window.year, timeZone: calendar.timeZone)

                XCTAssertEqual(span?.start, monday, "\(zone) \(window.year) Monday")
                XCTAssertEqual(span?.end, nextMonday, "\(zone) \(window.year) exclusive end")
                XCTAssertFalse(
                    ThanksgivingWindow.contains(sundayBefore, calendar: calendar),
                    "\(zone) \(window.year) Sunday before"
                )
                XCTAssertTrue(
                    ThanksgivingWindow.contains(monday, calendar: calendar),
                    "\(zone) \(window.year) Monday"
                )
                XCTAssertTrue(
                    ThanksgivingWindow.contains(sundayLate, calendar: calendar),
                    "\(zone) \(window.year) Sunday 11:59pm"
                )
                XCTAssertFalse(
                    ThanksgivingWindow.contains(nextMonday, calendar: calendar),
                    "\(zone) \(window.year) next Monday"
                )
            }
        }
    }

    func test2026WindowMatchesThanksgivingWeek() {
        let newYork = calendar("America/New_York")
        XCTAssertFalse(ThanksgivingWindow.contains(
            date(newYork, year: 2026, month: 11, day: 22, hour: 23, minute: 59, second: 59),
            calendar: newYork
        ))
        XCTAssertTrue(ThanksgivingWindow.contains(
            date(newYork, year: 2026, month: 11, day: 23),
            calendar: newYork
        ))
        XCTAssertTrue(ThanksgivingWindow.contains(
            date(newYork, year: 2026, month: 11, day: 26, hour: 15),
            calendar: newYork
        ))
        XCTAssertTrue(ThanksgivingWindow.contains(
            date(newYork, year: 2026, month: 11, day: 29, hour: 23, minute: 59, second: 59),
            calendar: newYork
        ))
        XCTAssertFalse(ThanksgivingWindow.contains(
            date(newYork, year: 2026, month: 11, day: 30),
            calendar: newYork
        ))
    }

    func testUsesTheCalendarsTimeZone() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(
            timeZone: utc.timeZone,
            year: 2026, month: 11, day: 30, hour: 4, minute: 30
        ))!
        // 11:30pm Sunday in New York, already Monday morning in Paris.
        XCTAssertTrue(ThanksgivingWindow.contains(instant, calendar: calendar("America/New_York")))
        XCTAssertFalse(ThanksgivingWindow.contains(instant, calendar: calendar("Europe/Paris")))
    }

    func testNonGregorianCalendarStillUsesCivilThanksgiving() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let losAngeles = calendar("America/Los_Angeles")
        let mondayNoon = date(losAngeles, year: 2026, month: 11, day: 23, hour: 12)
        XCTAssertTrue(ThanksgivingWindow.contains(mondayNoon, calendar: japanese))
        let sundayBefore = date(losAngeles, year: 2026, month: 11, day: 22, hour: 21)
        XCTAssertFalse(ThanksgivingWindow.contains(sundayBefore, calendar: japanese))
    }

    func testOverrideForcesThemeOnOrOff() {
        let newYork = calendar("America/New_York")
        let during = date(newYork, year: 2026, month: 11, day: 26, hour: 12)
        let outside = date(newYork, year: 2026, month: 11, day: 22, hour: 12)
        XCTAssertTrue(ThanksgivingThemeGate.isActive(at: during, calendar: newYork, override: .automatic))
        XCTAssertFalse(ThanksgivingThemeGate.isActive(at: outside, calendar: newYork, override: .automatic))
        XCTAssertTrue(ThanksgivingThemeGate.isActive(at: outside, calendar: newYork, override: .on))
        XCTAssertFalse(ThanksgivingThemeGate.isActive(at: during, calendar: newYork, override: .off))
    }

    func testSeasonalIconIsOptInAndRestoresAfterTheWindow() {
        XCTAssertEqual(
            ThanksgivingIconPolicy.action(
                themeActive: true,
                optedIn: false,
                previousAlternateIconName: nil,
                activeAlternateIconName: nil
            ),
            .none
        )
        XCTAssertEqual(
            ThanksgivingIconPolicy.action(
                themeActive: true,
                optedIn: true,
                previousAlternateIconName: "AppIcon-Ember",
                activeAlternateIconName: ThanksgivingIconPolicy.seasonalAlternateIconName
            ),
            .none
        )
        XCTAssertEqual(
            ThanksgivingIconPolicy.action(
                themeActive: false,
                optedIn: true,
                previousAlternateIconName: "AppIcon-Ember",
                activeAlternateIconName: ThanksgivingIconPolicy.seasonalAlternateIconName
            ),
            .setAlternateIcon("AppIcon-Ember")
        )
        XCTAssertEqual(
            ThanksgivingIconPolicy.action(
                themeActive: false,
                optedIn: true,
                previousAlternateIconName: "",
                activeAlternateIconName: ThanksgivingIconPolicy.seasonalAlternateIconName
            ),
            .setAlternateIcon(nil)
        )
        XCTAssertEqual(
            ThanksgivingIconPolicy.action(
                themeActive: false,
                optedIn: true,
                previousAlternateIconName: "AppIcon-Dawn",
                activeAlternateIconName: "AppIcon-Dawn"
            ),
            .clearOptIn
        )
    }

    func testIconOfferOnlyDuringTheWindowUntilDismissedOrApplied() {
        XCTAssertTrue(ThanksgivingIconPolicy.shouldOffer(
            themeActive: true,
            supportsAlternateIcons: true,
            dismissedYear: nil,
            seasonYear: 2026,
            alreadyUsingSeasonal: false
        ))
        XCTAssertFalse(ThanksgivingIconPolicy.shouldOffer(
            themeActive: false,
            supportsAlternateIcons: true,
            dismissedYear: nil,
            seasonYear: 2026,
            alreadyUsingSeasonal: false
        ))
        XCTAssertFalse(ThanksgivingIconPolicy.shouldOffer(
            themeActive: true,
            supportsAlternateIcons: true,
            dismissedYear: 2026,
            seasonYear: 2026,
            alreadyUsingSeasonal: false
        ))
        XCTAssertTrue(ThanksgivingIconPolicy.shouldOffer(
            themeActive: true,
            supportsAlternateIcons: true,
            dismissedYear: 2025,
            seasonYear: 2026,
            alreadyUsingSeasonal: false
        ))
        XCTAssertFalse(ThanksgivingIconPolicy.shouldOffer(
            themeActive: true,
            supportsAlternateIcons: false,
            dismissedYear: nil,
            seasonYear: 2026,
            alreadyUsingSeasonal: false
        ))
        XCTAssertFalse(ThanksgivingIconPolicy.shouldOffer(
            themeActive: true,
            supportsAlternateIcons: true,
            dismissedYear: nil,
            seasonYear: 2026,
            alreadyUsingSeasonal: true
        ))
    }
}
