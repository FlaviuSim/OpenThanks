import XCTest
#if canImport(PostAcceptPrompt)
@testable import PostAcceptPrompt
#else
@testable import OpenThanks
#endif

final class PostAcceptPromptTests: XCTestCase {
    func testPayItForwardTitleUsesFirstName() {
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "Ada Lovelace"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "Ada"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "  Ada  Lovelace"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: nil), "someone thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: ""), "someone thanked you")
        XCTAssertFalse(PayItForwardPromptCopy.body.isEmpty)
        XCTAssertFalse(PayItForwardPromptCopy.reassurance.isEmpty)
        XCTAssertTrue(
            PayItForwardPromptCopy.reassurance.contains("Don’t worry about the wording")
                || PayItForwardPromptCopy.reassurance.contains("Don't worry about the wording")
        )
        XCTAssertEqual(PayItForwardPromptCopy.notNow, "Not now")
    }

    func testStartersMatchPaths() {
        XCTAssertTrue(
            PayItForwardPromptCopy.starter(for: .helpedThisWeek)
                .hasPrefix("Thank you for helping me this week")
        )
        XCTAssertTrue(
            PayItForwardPromptCopy.starter(for: .neverThanked)
                .contains("never properly thanked")
        )
        let echo = PayItForwardPromptCopy.starter(for: .echoGift, echoTheme: .jumpingIn)
        XCTAssertTrue(echo.contains("jumping in"))
        let cal = PayItForwardPromptCopy.starter(for: .calendarPerson, personName: "Jordan Lee")
        XCTAssertTrue(cal.contains("Jordan"))
        let thankBack = PayItForwardPromptCopy.thankBackMessage(
            fromName: "Ada Lovelace",
            acceptedMessage: "You really listened when I needed it."
        )
        XCTAssertTrue(thankBack.contains("Ada"))
        XCTAssertTrue(thankBack.contains("grateful") || thankBack.contains("meant a lot"))
        XCTAssertEqual(
            PayItForwardPromptCopy.thankBackChipTitle(fromName: "Ada Lovelace"),
            "Thank Ada back"
        )
    }

    func testEchoThemeDetection() {
        XCTAssertEqual(
            GratitudeEchoTheme.detect(from: "Thank you for jumping in when I was stuck."),
            .jumpingIn
        )
        XCTAssertEqual(
            GratitudeEchoTheme.detect(from: "You really listened when I needed it."),
            .listening
        )
        XCTAssertEqual(GratitudeEchoTheme.detect(from: "Nice note"), .general)
        XCTAssertEqual(
            PayItForwardPromptCopy.questionPaths(echoTheme: .jumpingIn),
            [.helpedThisWeek, .neverThanked, .echoGift]
        )
        XCTAssertEqual(
            PayItForwardPromptCopy.questionPaths(echoTheme: .general),
            [.helpedThisWeek, .neverThanked]
        )
    }

    func testFirstSendTipRetired() {
        XCTAssertFalse(show())
        XCTAssertFalse(show(hasSeenTip: false, hasOpenedComposer: false, hasSentAppreciation: false))
    }

    func testMarkComposerOpenedPersists() {
        let name = "PostAcceptPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(FirstSendTip.hasOpenedComposer(in: defaults))
        FirstSendTip.markComposerOpened(in: defaults)
        XCTAssertTrue(FirstSendTip.hasOpenedComposer(in: defaults))
        XCTAssertFalse(show(hasOpenedComposer: FirstSendTip.hasOpenedComposer(in: defaults)))
    }

    #if !canImport(PostAcceptPrompt)
    #endif

    private func show(
        hasSeenTip: Bool = false,
        isFeedTab: Bool = true,
        tabComposerPresented: Bool = false,
        searchActive: Bool = false,
        pendingAcceptCount: Int = 0,
        rippleSheetPresented: Bool = false,
        hasOpenedComposer: Bool = false,
        hasSentAppreciation: Bool = false
    ) -> Bool {
        FirstSendTip.shouldShow(
            hasSeenTip: hasSeenTip,
            isFeedTab: isFeedTab,
            tabComposerPresented: tabComposerPresented,
            searchActive: searchActive,
            pendingAcceptCount: pendingAcceptCount,
            rippleSheetPresented: rippleSheetPresented,
            hasOpenedComposer: hasOpenedComposer,
            hasSentAppreciation: hasSentAppreciation
        )
    }
}
