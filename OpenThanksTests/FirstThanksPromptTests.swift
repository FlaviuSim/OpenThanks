import XCTest
#if canImport(FirstThanksPrompt)
@testable import FirstThanksPrompt
#else
@testable import OpenThanks
#endif

final class FirstThanksPromptTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    // MARK: - Card eligibility

    func testCardWaitsUntilTheSecondVisitAndHidesAfterASend() {
        XCTAssertFalse(show(visit: 1))
        XCTAssertFalse(show(visit: 0))
        XCTAssertTrue(show(visit: 2))
        XCTAssertTrue(show(visit: 6))
        XCTAssertFalse(show(isSignedIn: false, visit: 4))
        XCTAssertFalse(show(hasSentThankYou: true, visit: 4))
        XCTAssertFalse(show(hasSentThankYou: true, visit: 2))
    }

    func testDismissHidesTheCardForThatVisitOnly() {
        XCTAssertFalse(show(visit: 2, dismissedOnVisit: 2))
        XCTAssertTrue(show(visit: 3, dismissedOnVisit: 2))
        XCTAssertFalse(show(visit: 3, dismissedOnVisit: 3))
        XCTAssertTrue(show(visit: 4, dismissedOnVisit: 3))
    }

    func testShownEventFiresOncePerVisit() {
        XCTAssertTrue(FirstThanksCardRule.shouldCaptureShown(visitNumber: 2, lastCapturedVisit: nil))
        XCTAssertFalse(FirstThanksCardRule.shouldCaptureShown(visitNumber: 2, lastCapturedVisit: 2))
        XCTAssertTrue(FirstThanksCardRule.shouldCaptureShown(visitNumber: 3, lastCapturedVisit: 2))
        XCTAssertFalse(FirstThanksCardRule.shouldCaptureShown(visitNumber: 0, lastCapturedVisit: nil))

        let name = "FirstThanksPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertTrue(FirstThanksCardRule.markShownIfNeeded(visitNumber: 2, in: defaults))
        XCTAssertFalse(FirstThanksCardRule.markShownIfNeeded(visitNumber: 2, in: defaults))
        FirstThanksCardRule.dismiss(visitNumber: 2, in: defaults)
        XCTAssertEqual(FirstThanksCardRule.dismissedVisit(in: defaults), 2)
        XCTAssertFalse(show(visit: 2, dismissedOnVisit: FirstThanksCardRule.dismissedVisit(in: defaults)))
        XCTAssertTrue(FirstThanksCardRule.markShownIfNeeded(visitNumber: 3, in: defaults))
    }

    // MARK: - Visits

    func testVisitStartsAtOneAndSurvivesAShortReturn() {
        let start = date("2026-11-02T15:00:00Z")
        var state = AppVisitState(number: 0, lastActivityAt: nil)
        state = AppVisit.advance(state: state, now: start, calendar: calendar)
        XCTAssertEqual(state.number, 1)

        let soon = start.addingTimeInterval(20 * 60)
        state = AppVisit.advance(state: state, now: soon, calendar: calendar)
        XCTAssertEqual(state.number, 1)

        let idle = soon.addingTimeInterval(AppVisit.inactivityGap)
        state = AppVisit.advance(state: state, now: idle, calendar: calendar)
        XCTAssertEqual(state.number, 2)
    }

    func testNewDayStartsAVisitEvenInsideTheIdleGap() {
        let late = date("2026-11-02T23:50:00Z")
        var state = AppVisit.advance(
            state: AppVisitState(number: 0, lastActivityAt: nil),
            now: late,
            calendar: calendar
        )
        let afterMidnight = date("2026-11-03T00:10:00Z")
        state = AppVisit.advance(state: state, now: afterMidnight, calendar: calendar)
        XCTAssertEqual(state.number, 2)
    }

    func testRecordReturnPersistsAndNoteActivityDoesNotIncrement() {
        let name = "FirstThanksPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let start = date("2026-11-04T12:00:00Z")
        XCTAssertEqual(AppVisit.recordReturn(in: defaults, now: start, calendar: calendar), 1)
        AppVisit.noteActivity(in: defaults, now: start.addingTimeInterval(90 * 60))
        XCTAssertEqual(
            AppVisit.recordReturn(in: defaults, now: start.addingTimeInterval(100 * 60), calendar: calendar),
            1
        )
        XCTAssertEqual(
            AppVisit.recordReturn(in: defaults, now: start.addingTimeInterval(100 * 60 + AppVisit.inactivityGap), calendar: calendar),
            2
        )
    }

    // MARK: - Suggestions

    func testPeopleSourcesWinAndRelationshipsAreTheFallback() {
        let empty = FirstThanksSuggestions.resolve([])
        XCTAssertEqual(empty.kind, .relationships)
        XCTAssertEqual(
            empty.items,
            FirstThanksRelationship.allCases.map { FirstThanksSuggestion.relationship($0) }
        )

        let mixed = FirstThanksSuggestions.resolve([
            FirstThanksCandidate(id: "recent", name: "Sam", source: .recent),
            FirstThanksCandidate(id: "cal", name: "Sam", source: .calendar),
            FirstThanksCandidate(id: "thanks", name: "  Maya  ", source: .thankedYou),
            FirstThanksCandidate(id: "blank", name: "   ", source: .thankedYou),
            FirstThanksCandidate(id: "coach", name: "Coach Lee", source: .calendar),
            FirstThanksCandidate(id: "friend", name: "Priya", source: .recent),
            FirstThanksCandidate(id: "extra", name: "Noah", source: .recent),
        ])
        XCTAssertEqual(mixed.kind, .people)
        XCTAssertEqual(mixed.items, [
            .person(id: "thanks", name: "Maya", source: .thankedYou),
            .person(id: "coach", name: "Coach Lee", source: .calendar),
            .person(id: "cal", name: "Sam", source: .calendar),
        ])
    }

    // MARK: - Home view

    func testHomeViewFiresOnFirstShowAndReTapStillCounts() {
        let now = date("2026-11-05T12:00:00Z")
        XCTAssertTrue(HomeScreenView.shouldCapture(lastCapturedAt: nil, now: now))
        XCTAssertFalse(HomeScreenView.shouldCapture(
            lastCapturedAt: now,
            now: now.addingTimeInterval(0.4)
        ))
        XCTAssertTrue(HomeScreenView.shouldCapture(
            lastCapturedAt: now,
            now: now.addingTimeInterval(0.4),
            force: true
        ))
        XCTAssertTrue(HomeScreenView.shouldCapture(
            lastCapturedAt: now,
            now: now.addingTimeInterval(HomeScreenView.duplicateWindow)
        ))
        XCTAssertEqual(HomeScreenView.event, "home_viewed")
    }

    private func show(
        isSignedIn: Bool = true,
        hasSentThankYou: Bool = false,
        visit: Int,
        dismissedOnVisit: Int? = nil
    ) -> Bool {
        FirstThanksCardRule.shouldShow(
            isSignedIn: isSignedIn,
            hasSentThankYou: hasSentThankYou,
            visitNumber: visit,
            dismissedOnVisit: dismissedOnVisit
        )
    }
}
