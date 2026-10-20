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

    func testLookupRunsOncePerColdLaunchUnlessForced() {
        XCTAssertTrue(AppUpdateChecker.shouldLookup(force: false, alreadyLookedUpThisProcess: false))
        XCTAssertFalse(AppUpdateChecker.shouldLookup(force: false, alreadyLookedUpThisProcess: true))
        XCTAssertTrue(AppUpdateChecker.shouldLookup(force: true, alreadyLookedUpThisProcess: true))
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

final class DeliverRecipientGuidanceTests: XCTestCase {
    func testGuestEmailCopy() {
        XCTAssertEqual(
            DeliverRecipientGuidance.line(for: .guestEmail),
            "We’ll email this person the link"
        )
    }

    func testNameOnlyCopyIncludesName() {
        XCTAssertEqual(
            DeliverRecipientGuidance.line(for: .nameOnly("Ada")),
            "Share the link with Ada to accept"
        )
    }

    func testMemberCopy() {
        XCTAssertEqual(
            DeliverRecipientGuidance.line(for: .member),
            "We’ll notify them — and you can share the link too"
        )
    }
}

final class DeliverMailtoTests: XCTestCase {
    func testPrefersConfirmedThenDraftThenProfile() {
        XCTAssertEqual(
            DeliverMailto.toAddress(
                confirmed: "a@example.com",
                draft: "b@example.com",
                profileEmail: "c@example.com"
            ),
            "a@example.com"
        )
        XCTAssertEqual(
            DeliverMailto.toAddress(
                confirmed: nil,
                draft: "b@example.com",
                profileEmail: "c@example.com"
            ),
            "b@example.com"
        )
        XCTAssertEqual(
            DeliverMailto.toAddress(
                confirmed: "  ",
                draft: nil,
                profileEmail: "c@example.com"
            ),
            "c@example.com"
        )
        XCTAssertNil(DeliverMailto.toAddress(confirmed: "not-an-email", draft: nil, profileEmail: nil))
    }
}

final class ShareScreenIdentityTests: XCTestCase {
    func testIdentityIgnoresRecipientFields() {
        let id = UUID()
        let a = ShareScreenIdentity.make(id: id, message: "Thanks", mediaUrl: nil)
        let b = ShareScreenIdentity.make(id: id, message: "Thanks", mediaUrl: nil)
        XCTAssertEqual(a, b)
        XCTAssertFalse(a.contains("@"))
        let edited = ShareScreenIdentity.make(id: id, message: "Thanks again", mediaUrl: nil)
        XCTAssertNotEqual(a, edited)
    }
}
