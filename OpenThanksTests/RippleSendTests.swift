import XCTest
#if canImport(RippleSend)
@testable import RippleSend
#else
@testable import OpenThanks
#endif

final class RippleSendTests: XCTestCase {
    private let viewer = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let profile = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let receivedId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let sentId = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!

    func testTapEventAndComposeSource() {
        let launch = RippleSend.launch(
            isOwnProfile: true,
            profileId: profile,
            viewerId: viewer,
            examples: []
        )

        XCTAssertEqual(launch.analyticsEvent, "ripple_send_tapped")
        XCTAssertEqual(launch.composeAnalyticsSource, "ripple_send_like_this")
        XCTAssertNotEqual(launch.composeAnalyticsSource, "ripple_tab")
        XCTAssertTrue(launch.isOwnProfile)
        XCTAssertEqual(launch.profileId, "11111111-2222-3333-4444-555555555555")
        XCTAssertNil(launch.inspiredByGratitudeId)
        XCTAssertNil(launch.inspiredByAuthorName)

        let properties = launch.analyticsProperties()
        XCTAssertEqual(properties["is_own_profile"] as? Bool, true)
        XCTAssertEqual(properties["profile_id"] as? String, launch.profileId)
        XCTAssertNil(properties["parent_gratitude_id"])
        XCTAssertNil(properties["inspired_by_author_name"])
    }

    func testPrefillsWhenAnOnScreenExampleWasReceivedByTheViewer() {
        let launch = RippleSend.launch(
            isOwnProfile: true,
            profileId: profile,
            viewerId: viewer,
            examples: [
                RippleSend.Example(id: sentId, recipientId: UUID(), authorName: "Not this one"),
                RippleSend.Example(id: receivedId, recipientId: viewer, authorName: "  Ada Lovelace  "),
            ]
        )

        XCTAssertEqual(launch.inspiredByGratitudeId, receivedId)
        XCTAssertEqual(launch.inspiredByAuthorName, "Ada Lovelace")
        XCTAssertEqual(
            launch.analyticsProperties()["parent_gratitude_id"] as? String,
            "aaaaaaaa-0000-0000-0000-000000000001"
        )
        XCTAssertNil(launch.analyticsProperties()["inspired_by_author_name"])
    }

    func testSkipsInspirationContextWhenNothingOnScreenWasReceived() {
        let someoneElse = UUID()
        let launch = RippleSend.launch(
            isOwnProfile: false,
            profileId: profile,
            viewerId: viewer,
            examples: [
                RippleSend.Example(id: sentId, recipientId: someoneElse, authorName: "Sam"),
                RippleSend.Example(id: receivedId, recipientId: nil, authorName: "Sam"),
            ]
        )

        XCTAssertFalse(launch.isOwnProfile)
        XCTAssertNil(launch.inspiredByGratitudeId)
        XCTAssertNil(launch.inspiredByAuthorName)
        XCTAssertNil(launch.analyticsProperties()["parent_gratitude_id"])
    }

    func testBlankAuthorNameDoesNotBecomeInspiredByCopy() {
        let launch = RippleSend.launch(
            isOwnProfile: true,
            profileId: profile,
            viewerId: viewer,
            examples: [
                RippleSend.Example(id: receivedId, recipientId: viewer, authorName: "   "),
            ]
        )

        XCTAssertEqual(launch.inspiredByGratitudeId, receivedId)
        XCTAssertNil(launch.inspiredByAuthorName)
    }

    func testNoViewerMeansNoInspirationContext() {
        let launch = RippleSend.launch(
            isOwnProfile: false,
            profileId: profile,
            viewerId: nil,
            examples: [
                RippleSend.Example(id: receivedId, recipientId: viewer, authorName: "Ada"),
            ]
        )

        XCTAssertNil(launch.inspiredByGratitudeId)
        XCTAssertNil(launch.inspiredByAuthorName)
    }
}
