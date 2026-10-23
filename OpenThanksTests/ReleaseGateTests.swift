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

final class CalendarSelfIdentityTests: XCTestCase {
    func testCollectMergesProfileAccountIdentitiesAndRemembered() {
        let identity = CalendarSelfIdentity.collect(
            profileEmail: "apple@icloud.com",
            profileFullName: "Flaviu Sim",
            accountEmail: "relay@privaterelay.appleid.com",
            identityEmails: ["work@company.com", "not-an-email"],
            googleCalendarEmail: "me@gmail.com",
            remembered: ["alias@company.com"]
        )
        XCTAssertEqual(
            identity.emails,
            [
                "apple@icloud.com",
                "relay@privaterelay.appleid.com",
                "work@company.com",
                "me@gmail.com",
                "alias@company.com",
            ]
        )
        XCTAssertTrue(identity.fullNames.contains("flaviu sim"))
    }

    func testMatchesOtherInboxAndFullNameButNotFirstNameAlone() {
        let identity = CalendarSelfIdentity.collect(
            profileEmail: "apple@icloud.com",
            profileFullName: "Flaviu Sim",
            remembered: []
        )
        let workSelf = CalendarAttendee(name: "Flaviu", email: "apple@icloud.com", isCurrentUser: false)
        let namedSelf = CalendarAttendee(name: "Flaviu Sim", email: "other@x.com", isCurrentUser: false)
        let otherAlex = CalendarAttendee(name: "Alex", email: "alex@x.com", isCurrentUser: false)
        let colleague = CalendarAttendee(name: "Jordan Lee", email: "jordan@x.com", isCurrentUser: false)

        XCTAssertTrue(identity.matches(attendee: workSelf))
        XCTAssertTrue(identity.matches(attendee: namedSelf))
        XCTAssertFalse(identity.matches(attendee: otherAlex))
        XCTAssertFalse(identity.matches(attendee: colleague))
    }

    func testSanitizedMeetingTopicStripsAuthorName() {
        let identity = CalendarSelfIdentity.collect(
            profileFullName: "Flaviu Sim",
            remembered: []
        )
        XCTAssertEqual(identity.sanitizedMeetingTopic("Flaviu Sim / Jordan Lee"), "Jordan Lee")
        XCTAssertEqual(identity.sanitizedMeetingTopic("Jordan and Flaviu Sim"), "Jordan")
        XCTAssertNil(identity.sanitizedMeetingTopic("Flaviu Sim / 1:1"))
    }

    func testHarvestedSelfIdentityFromMarkedAttendees() {
        let meeting = CalendarMeeting(
            id: "1",
            title: "Sync",
            start: Date(),
            end: Date().addingTimeInterval(1800),
            isAllDay: false,
            isCancelled: false,
            isRecurring: false,
            attendees: [
                CalendarAttendee(name: "Flaviu Sim", email: "work@company.com", isCurrentUser: true),
                CalendarAttendee(name: "Jordan", email: "jordan@x.com", isCurrentUser: false),
            ]
        )
        let harvested = GratitudeOpportunityRanker.harvestedSelfIdentity(from: [meeting])
        XCTAssertTrue(harvested.emails.contains("work@company.com"))
        XCTAssertTrue(harvested.fullNames.contains("flaviu sim"))
    }
}
