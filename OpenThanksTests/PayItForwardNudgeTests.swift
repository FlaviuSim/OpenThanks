import XCTest
@testable import OpenThanks

final class PayItForwardNudgeTests: XCTestCase {
    func testThankBackTitleUsesSenderFirstName() {
        XCTAssertEqual(PayItForwardNudgeCard.thankBackTitle(for: "Ada Lovelace"), "Thank Ada back")
        XCTAssertEqual(PayItForwardNudgeCard.thankBackTitle(for: "Ada"), "Thank Ada back")
    }

    func testThankBackEventIncludesParentGratitudeId() {
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let props = PayItForwardNudgeCard.thankBackProperties(parentGratitudeId: id)
        XCTAssertEqual(PayItForwardNudgeCard.thankBackEventName, "thank_back_tapped")
        XCTAssertEqual(
            props["parent_gratitude_id"] as? String,
            "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        )
    }
}
