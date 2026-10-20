import XCTest
@testable import OpenThanks

final class PayItForwardNudgeTests: XCTestCase {
    func testSenderFirstNameUsesTheFirstWordOrSomeone() {
        XCTAssertEqual(PayItForwardNudgeBehavior.senderFirstName(from: nil), "someone")
        XCTAssertEqual(PayItForwardNudgeBehavior.senderFirstName(from: ""), "someone")
        XCTAssertEqual(PayItForwardNudgeBehavior.senderFirstName(from: "Ada"), "Ada")
        XCTAssertEqual(PayItForwardNudgeBehavior.senderFirstName(from: "Ada Lovelace"), "Ada")
        XCTAssertEqual(PayItForwardNudgeBehavior.senderFirstName(from: "  Ada Lovelace"), "Ada")
    }

    func testExistingPromptCopyStaysTheSame() {
        XCTAssertEqual(PayItForwardNudgeBehavior.primaryButtonTitle, "Thank someone next")
        XCTAssertEqual(PayItForwardNudgeBehavior.notNowTitle, "Not now")
        XCTAssertEqual(PayItForwardNudgeBehavior.dismissAccessibilityLabel, "Dismiss")
        XCTAssertEqual(
            PayItForwardNudgeBehavior.promptBody(from: "Ada Lovelace"),
            "Ada just thanked you. Send one note to someone who deserves it — keep their kindness moving."
        )
        XCTAssertEqual(
            PayItForwardNudgeBehavior.promptBody(from: nil),
            "someone just thanked you. Send one note to someone who deserves it — keep their kindness moving."
        )
        XCTAssertEqual(
            PayItForwardNudgeBehavior.rippleCaption(from: "Ada Lovelace"),
            "Ripple started by Ada"
        )
        XCTAssertEqual(
            PayItForwardNudgeBehavior.rippleCaption(from: ""),
            "Ripple started by someone"
        )
    }

    func testThankSomeoneStillForwardsDismissesAndAsksForReview() {
        let plan = PayItForwardNudgeBehavior.sheetTapPlan(.thankSomeoneElse)
        XCTAssertTrue(plan.forwardsThankSomeone)
        XCTAssertTrue(plan.dismissesSheet)
        XCTAssertTrue(plan.schedulesReviewPrompt)
        XCTAssertNotEqual(
            PayItForwardNudgeBehavior.primaryButtonTitle,
            PayItForwardNudgeBehavior.thankBackButtonTitle(from: "Ada Lovelace")
        )
    }

    func testDismissAndNotNowStillOnlyCloseTheSheet() {
        let plan = PayItForwardNudgeBehavior.sheetTapPlan(.dismiss)
        XCTAssertFalse(plan.forwardsThankSomeone)
        XCTAssertTrue(plan.dismissesSheet)
        XCTAssertTrue(plan.schedulesReviewPrompt)
    }

    func testShownImpressionStillRequiresEveryFieldAndFiresOnce() {
        let parentId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let shown = PayItForwardNudgeBehavior.shownCapture(
            alreadyCaptured: false,
            parentId: parentId,
            surface: "feed",
            source: "feed_accept"
        )
        XCTAssertEqual(shown?.parentId, parentId)
        XCTAssertEqual(shown?.surface, "feed")
        XCTAssertEqual(shown?.source, "feed_accept")

        XCTAssertNil(
            PayItForwardNudgeBehavior.shownCapture(
                alreadyCaptured: true,
                parentId: parentId,
                surface: "feed",
                source: "feed_accept"
            )
        )
        XCTAssertNil(
            PayItForwardNudgeBehavior.shownCapture(
                alreadyCaptured: false,
                parentId: nil,
                surface: "feed",
                source: "feed_accept"
            )
        )
        XCTAssertNil(
            PayItForwardNudgeBehavior.shownCapture(
                alreadyCaptured: false,
                parentId: parentId,
                surface: nil,
                source: "feed_accept"
            )
        )
        XCTAssertNil(
            PayItForwardNudgeBehavior.shownCapture(
                alreadyCaptured: false,
                parentId: parentId,
                surface: "feed",
                source: nil
            )
        )
    }

    func testThankBackTitleUsesTheSenderFirstName() {
        XCTAssertEqual(
            PayItForwardNudgeBehavior.thankBackButtonTitle(from: "Ada Lovelace"),
            "Thank Ada back"
        )
        XCTAssertEqual(
            PayItForwardNudgeBehavior.thankBackButtonTitle(from: nil),
            "Thank someone back"
        )
        XCTAssertEqual(
            PayItForwardNudgeBehavior.thankBackButtonTitle(from: ""),
            "Thank someone back"
        )
    }

    func testThankBackPrefillsTheSenderAndRecordsTheParentGratitude() {
        let parentId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let launch = PayItForwardNudgeBehavior.thankBackLaunch(fromName: "  Ada Lovelace  ")
        XCTAssertEqual(launch.recipientName, "Ada Lovelace")
        XCTAssertNotEqual(launch.recipientName, "Ada")
        XCTAssertEqual(launch.analyticsSource, "post_accept_thank_back")

        let capture = PayItForwardNudgeBehavior.thankBackCapture(parentGratitudeId: parentId)
        XCTAssertEqual(capture.event, "thank_back_tapped")
        XCTAssertEqual(capture.parentGratitudeId, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(
            capture.properties["parent_gratitude_id"] as? String,
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
        XCTAssertEqual(capture.properties.count, 1)

        let missing = PayItForwardNudgeBehavior.thankBackCapture(parentGratitudeId: nil)
        XCTAssertEqual(missing.event, "thank_back_tapped")
        XCTAssertNil(missing.parentGratitudeId)
        XCTAssertTrue(missing.properties.isEmpty)

        XCTAssertNil(PayItForwardNudgeBehavior.thankBackLaunch(fromName: nil).recipientName)
        XCTAssertNil(PayItForwardNudgeBehavior.thankBackLaunch(fromName: "   ").recipientName)
    }
}
