import XCTest
#if canImport(CalendarPrompt)
@testable import CalendarPrompt
#else
@testable import OpenThanks
#endif

final class CalendarPromptCapTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testAutomaticPromptShowsAtMostTwice() {
        XCTAssertTrue(show(source: .deferredOpen, shownCount: 0))
        XCTAssertTrue(show(source: .postSend, shownCount: 1))
        XCTAssertFalse(show(source: .deferredOpen, shownCount: 2))
        XCTAssertFalse(show(source: .postSend, shownCount: 3))
    }

    func testNeverShowsInTheSessionAfterAnAccept() {
        XCTAssertFalse(show(source: .postAccept, shownCount: 0))
        XCTAssertFalse(show(source: .postAccept, shownCount: 0, acceptedThisSession: false))
        XCTAssertFalse(show(source: .deferredOpen, shownCount: 0, acceptedThisSession: true))
        XCTAssertFalse(show(source: .postSend, shownCount: 1, acceptedThisSession: true))
    }

    func testConnectedOrCoolingDownStaysHiddenAndExplicitConnectDoesNot() {
        XCTAssertFalse(show(source: .deferredOpen, shownCount: 0, calendarConnected: true))
        XCTAssertFalse(show(
            source: .postSend,
            shownCount: 0,
            cooldownUntil: now.addingTimeInterval(60)
        ))
        XCTAssertTrue(show(
            source: .postSend,
            shownCount: 0,
            cooldownUntil: now.addingTimeInterval(-60)
        ))
        XCTAssertTrue(show(source: .userInitiated, shownCount: 9, acceptedThisSession: true, calendarConnected: true))
    }

    func testOpenCountInfersShowsSpentBeforeTheCounterExisted() {
        XCTAssertEqual(CalendarPromptCap.inferredShownCount(mainAppOpenCount: 1), 0)
        XCTAssertEqual(CalendarPromptCap.inferredShownCount(mainAppOpenCount: 3), 0)
        XCTAssertEqual(CalendarPromptCap.inferredShownCount(mainAppOpenCount: 4), 1)
        XCTAssertEqual(CalendarPromptCap.inferredShownCount(mainAppOpenCount: 20), 2)
        XCTAssertEqual(CalendarPromptCap.effectiveShownCount(stored: nil, mainAppOpenCount: 20), 2)
        XCTAssertEqual(CalendarPromptCap.effectiveShownCount(stored: 1, mainAppOpenCount: 20), 1)
        XCTAssertFalse(show(
            source: .deferredOpen,
            shownCount: CalendarPromptCap.effectiveShownCount(stored: nil, mainAppOpenCount: 20)
        ))
    }

    func testRecordPersistsInUserDefaultsAndIgnoresADoubleAppear() {
        let name = "CalendarPromptCapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertEqual(CalendarPromptCap.load(from: defaults, mainAppOpenCount: 3), 0)

        CalendarPromptCap.record(in: defaults, mainAppOpenCount: 3, now: now)
        CalendarPromptCap.record(in: defaults, mainAppOpenCount: 3, now: now.addingTimeInterval(1))
        XCTAssertEqual(defaults.integer(forKey: CalendarPromptCap.shownCountKey), 1)
        XCTAssertEqual(CalendarPromptCap.load(from: defaults, mainAppOpenCount: 30), 1)

        CalendarPromptCap.record(
            in: defaults,
            mainAppOpenCount: 4,
            now: now.addingTimeInterval(CalendarPromptCap.duplicateAppearWindow + 1)
        )
        XCTAssertEqual(defaults.integer(forKey: CalendarPromptCap.shownCountKey), 2)
        XCTAssertFalse(show(
            source: .deferredOpen,
            shownCount: CalendarPromptCap.load(from: defaults, mainAppOpenCount: 4)
        ))
    }

    func testAutomaticPromptWaitsUntilTheFirstThankYou() {
        XCTAssertFalse(show(source: .deferredOpen, shownCount: 0, hasSentFirstThankYou: false))
        XCTAssertFalse(show(source: .postSend, shownCount: 0, hasSentFirstThankYou: false))
        XCTAssertTrue(show(source: .deferredOpen, shownCount: 0, hasSentFirstThankYou: true))
        XCTAssertTrue(show(source: .postSend, shownCount: 1, hasSentFirstThankYou: true))
        XCTAssertTrue(show(source: .userInitiated, shownCount: 0, hasSentFirstThankYou: false))
        XCTAssertFalse(show(source: .postAccept, shownCount: 0, hasSentFirstThankYou: true))
    }

    func testOpensBeforeTheFirstSendDoNotSpendTheAutomaticCap() {
        XCTAssertEqual(
            CalendarPromptCap.shownCountForAutomaticPrompt(
                stored: nil,
                preSendOpensIgnored: true,
                mainAppOpenCount: 20
            ),
            0
        )
        XCTAssertTrue(show(
            source: .deferredOpen,
            shownCount: 0,
            hasSentFirstThankYou: true
        ))
        XCTAssertEqual(
            CalendarPromptCap.shownCountForAutomaticPrompt(
                stored: nil,
                preSendOpensIgnored: false,
                mainAppOpenCount: 20
            ),
            2
        )
        XCTAssertEqual(
            CalendarPromptCap.shownCountForAutomaticPrompt(
                stored: 1,
                preSendOpensIgnored: true,
                mainAppOpenCount: 20
            ),
            1
        )

        let name = "CalendarPromptCapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        CalendarPromptCap.notePreSendOpensIgnoredIfNeeded(hasSentFirstThankYou: false, in: defaults)
        XCTAssertEqual(CalendarPromptCap.load(from: defaults, mainAppOpenCount: 12), 0)
        CalendarPromptCap.record(in: defaults, mainAppOpenCount: 12, now: now)
        XCTAssertEqual(defaults.integer(forKey: CalendarPromptCap.shownCountKey), 1)
        CalendarPromptCap.notePreSendOpensIgnoredIfNeeded(hasSentFirstThankYou: true, in: defaults)
        XCTAssertTrue(defaults.bool(forKey: CalendarPromptCap.preSendOpensIgnoredKey))
    }

    func testPeopleAlreadyPastTwoOpensDoNotGetAnotherAutomaticPrompt() {
        let name = "CalendarPromptCapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let shown = CalendarPromptCap.load(from: defaults, mainAppOpenCount: 12)
        XCTAssertEqual(shown, CalendarPromptCap.maximumAutomaticShows)
        XCTAssertFalse(show(source: .postSend, shownCount: shown))
        XCTAssertNil(defaults.object(forKey: CalendarPromptCap.shownCountKey))
    }

    private func show(
        source: CalendarPromptSource,
        shownCount: Int,
        acceptedThisSession: Bool = false,
        calendarConnected: Bool = false,
        cooldownUntil: Date? = nil,
        hasSentFirstThankYou: Bool = true
    ) -> Bool {
        CalendarPromptCap.shouldShowAutomatic(
            source: source,
            shownCount: shownCount,
            acceptedThisSession: acceptedThisSession,
            calendarConnected: calendarConnected,
            now: now,
            cooldownUntil: cooldownUntil,
            hasSentFirstThankYou: hasSentFirstThankYou
        )
    }
}
