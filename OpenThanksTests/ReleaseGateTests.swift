import XCTest
@testable import OpenThanks

final class HomeGateTaskTests: XCTestCase {
    func testTaskIDUsesOnlyUserAndProfileResolution() {
        let id = UUID()
        XCTAssertEqual(
            HomeGateTask.taskID(userId: id, hasResolvedProfile: true),
            "\(id.uuidString)-true"
        )
        XCTAssertEqual(
            HomeGateTask.taskID(userId: id, hasResolvedProfile: false),
            "\(id.uuidString)-false"
        )
        XCTAssertEqual(
            HomeGateTask.taskID(userId: nil, hasResolvedProfile: false),
            "out-false"
        )
    }

    func testTaskIDStableAcrossPermissionFlagFlips() {
        let id = UUID()
        let a = HomeGateTask.taskID(userId: id, hasResolvedProfile: true)
        let b = HomeGateTask.taskID(userId: id, hasResolvedProfile: true)
        XCTAssertEqual(a, b)
        // Intentionally does not encode open-count / AppStorage — those change during resolve.
        XCTAssertFalse(a.contains("hasCompleted"))
    }
}

final class AppUpdateVersionTests: XCTestCase {
    func testSemanticVersionOrdering() {
        XCTAssertTrue(AppUpdateChecker.isVersion("1.4", lessThan: "1.5"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.5", lessThan: "1.5.1"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.5.0", lessThan: "1.5.1"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.5", lessThan: "1.5"))
        XCTAssertFalse(AppUpdateChecker.isVersion("1.5", lessThan: "1.4"))
        XCTAssertTrue(AppUpdateChecker.isVersion("1.4.9", lessThan: "1.5"))
    }

    func testRecheckIsFasterWhenCacheSaysUpToDate() {
        let whenBehind = AppUpdateChecker.recheckInterval(installed: "1.4", cachedStore: "1.5")
        let whenCurrent = AppUpdateChecker.recheckInterval(installed: "1.4", cachedStore: "1.4")
        XCTAssertGreaterThan(whenBehind, whenCurrent)
        XCTAssertEqual(whenBehind, 24 * 60 * 60)
        XCTAssertEqual(whenCurrent, 15 * 60)
    }
}

final class FeedPagingTests: XCTestCase {
    func testListPageSizeIsBoundedForProgressiveLoading() {
        XCTAssertEqual(GratitudeService.listPageSize, 20)
        XCTAssertGreaterThan(GratitudeService.listPageSize, 0)
        XCTAssertLessThanOrEqual(GratitudeService.listPageSize, 50)
    }
}

final class UITestBootstrapTests: XCTestCase {
    func testArgumentConstantsAreStable() {
        XCTAssertEqual(UITestBootstrap.uiTestingArgument, "-ui-testing")
        XCTAssertEqual(UITestBootstrap.signedOutArgument, "-ui-testing-signed-out")
        XCTAssertEqual(UITestBootstrap.demoLoginArgument, "-ui-testing-demo-login")
        XCTAssertEqual(UITestBootstrap.freshInstallArgument, "-ui-testing-fresh")
    }
}
