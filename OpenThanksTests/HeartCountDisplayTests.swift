import XCTest
#if canImport(HeartCountDisplay)
@testable import HeartCountDisplay
#else
@testable import OpenThanks
#endif

final class HeartCountDisplayTests: XCTestCase {
    func testPrefersLiveOverEmbedded() {
        XCTAssertEqual(HeartCountDisplay.resolve(embedded: 0, live: 2), 2)
        XCTAssertEqual(HeartCountDisplay.resolve(embedded: 3, live: 1), 3)
    }

    func testViewerHeartFloorsAtOne() {
        // Stale embed of 0 while the viewer has hearted (screenshot bug).
        XCTAssertEqual(
            HeartCountDisplay.resolve(embedded: 0, live: 0, viewerHasHearted: true),
            1
        )
        XCTAssertEqual(
            HeartCountDisplay.resolve(embedded: 0, live: 4, viewerHasHearted: true),
            4
        )
    }

    func testUnheartedZeroStaysZero() {
        XCTAssertEqual(
            HeartCountDisplay.resolve(embedded: 0, live: 0, viewerHasHearted: false),
            0
        )
    }
}
