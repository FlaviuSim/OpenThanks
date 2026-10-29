import XCTest
#if canImport(PostAcceptPrompt)
@testable import PostAcceptPrompt
#else
@testable import OpenThanks
#endif

final class PostAcceptPromptTests: XCTestCase {
    func testRippleSheetCopy() {
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "Ada Lovelace"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "Ada"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: "  Ada  Lovelace"), "Ada thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: nil), "someone thanked you")
        XCTAssertEqual(PayItForwardPromptCopy.title(fromName: ""), "someone thanked you")
        XCTAssertEqual(
            PayItForwardPromptCopy.body,
            "Send one note to someone else, if you want their kindness to keep going."
        )
        XCTAssertEqual(PayItForwardPromptCopy.primaryButton, "Send a note")
        XCTAssertEqual(PayItForwardPromptCopy.notNow, "Not now")

        let sheet = [
            PayItForwardPromptCopy.title(fromName: "Ada"),
            PayItForwardPromptCopy.body,
            PayItForwardPromptCopy.primaryButton,
            PayItForwardPromptCopy.notNow,
        ].joined(separator: "\n")
        XCTAssertFalse(sheet.contains("Continue the ripple"))
        XCTAssertFalse(sheet.contains("Ripple started by"))
        XCTAssertFalse(sheet.contains("Thank someone next"))
        XCTAssertFalse(sheet.contains("just thanked you"))
    }

    func testFirstSendTipCopy() {
        XCTAssertEqual(FirstSendTip.title, "The heart below starts a note")
        XCTAssertEqual(FirstSendTip.detail, "Tap it when you know who it's for.")
        let tip = "\(FirstSendTip.title)\n\(FirstSendTip.detail)"
        XCTAssertFalse(tip.contains("Start sending your first appreciation"))
        XCTAssertFalse(tip.contains("Tap the heart button below"))
    }

    func testTipShowsOnFeedWhenNothingElseIsInTheWay() {
        XCTAssertTrue(show())
    }

    func testTipHidesWhileTheRippleSheetIsPresented() {
        XCTAssertFalse(show(rippleSheetPresented: true))
    }

    func testTipShowsAgainAfterNotNowWhenTheyHaveNotComposedOrSent() {
        XCTAssertTrue(show(rippleSheetPresented: false))
    }

    func testTipHidesAfterTheComposerWasOpenedOrAnAppreciationWasSent() {
        XCTAssertFalse(show(hasOpenedComposer: true))
        XCTAssertFalse(show(hasSentAppreciation: true))
        XCTAssertFalse(show(
            rippleSheetPresented: false,
            hasOpenedComposer: true,
            hasSentAppreciation: true
        ))
    }

    func testTipKeepsTheExistingHomeGates() {
        XCTAssertFalse(show(hasSeenTip: true))
        XCTAssertFalse(show(isFeedTab: false))
        XCTAssertFalse(show(tabComposerPresented: true))
        XCTAssertFalse(show(searchActive: true))
        XCTAssertFalse(show(pendingAcceptCount: 1))
        XCTAssertFalse(show(pendingAcceptCount: 2, rippleSheetPresented: true))
    }

    func testMarkComposerOpenedHidesTheTipOnTheNextCheck() {
        let name = "PostAcceptPromptTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        XCTAssertFalse(FirstSendTip.hasOpenedComposer(in: defaults))
        FirstSendTip.markComposerOpened(in: defaults)
        XCTAssertTrue(FirstSendTip.hasOpenedComposer(in: defaults))
        XCTAssertFalse(show(hasOpenedComposer: FirstSendTip.hasOpenedComposer(in: defaults)))
    }

    #if !canImport(PostAcceptPrompt)
    func testSentFlagUsesTheExistingDeviceSendCounter() {
        XCTAssertEqual(
            EnjoymentPrompt.successfulSendCountKey,
            "enjoymentPrompt.successfulSendCount.v1"
        )
    }
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
