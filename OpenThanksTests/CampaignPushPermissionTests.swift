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

    func testContextLineIsReceiveAppreciationAndDoesNotMentionWatch() {
        XCTAssertEqual(
            CampaignPushPermission.contextLine,
            "Get Notified When you Receive an Appreciation"
        )
        XCTAssertEqual(
            CampaignPushPermission.contextDetail,
            "We promise not to bother you unnecessarily."
        )
        let copy = [
            CampaignPushPermission.contextLine,
            CampaignPushPermission.contextDetail,
        ].joined(separator: " ").lowercased()
        XCTAssertFalse(copy.contains("watch"))
    }
}
