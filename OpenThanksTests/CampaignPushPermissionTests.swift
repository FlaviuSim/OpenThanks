import XCTest
#if canImport(CampaignPush)
@testable import CampaignPush
#else
@testable import OpenThanks
#endif

final class CampaignPushPermissionTests: XCTestCase {
    func testAsksOnlyWhenUndetermined() {
        for moment: CampaignPushMoment in [.openedScreen, .joined] {
            XCTAssertTrue(CampaignPushPermission.shouldRequest(
                .notDetermined,
                moment: moment,
                alreadyOfferedThisSession: false
            ))
            XCTAssertFalse(CampaignPushPermission.shouldRequest(
                .denied,
                moment: moment,
                alreadyOfferedThisSession: false
            ))
            XCTAssertFalse(CampaignPushPermission.shouldRequest(
                .authorized,
                moment: moment,
                alreadyOfferedThisSession: false
            ))
        }
    }

    func testDoesNotAskAgainAfterThisSessionAlreadyOffered() {
        for moment: CampaignPushMoment in [.openedScreen, .joined] {
            XCTAssertFalse(CampaignPushPermission.shouldRequest(
                .notDetermined,
                moment: moment,
                alreadyOfferedThisSession: true
            ))
        }
    }

    func testContextLineIsTheDailyPromptAndDoesNotMentionWatch() {
        XCTAssertEqual(
            CampaignPushPermission.contextLine,
            "Get your daily 30 Days of Thanks prompt."
        )
        let copy = [
            CampaignPushPermission.contextLine,
            CampaignPushPermission.contextDetail,
        ].joined(separator: " ").lowercased()
        XCTAssertFalse(copy.contains("watch"))
    }
}
