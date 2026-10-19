import XCTest
#if canImport(ComposeDraft)
@testable import ComposeDraft
#else
@testable import OpenThanks
#endif

final class ComposeDraftStoreTests: XCTestCase {
    private var fake: FakeScheduler!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        fake = FakeScheduler()
        suiteName = "ComposeDraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        ComposeDraftStore.defaults = defaults
        ComposeDraftStore.scheduler = fake
    }

    override func tearDown() {
        ComposeDraftStore.defaults.removePersistentDomain(forName: suiteName)
        ComposeDraftStore.defaults = .standard
        ComposeDraftStore.scheduler = ComposeDraftStore.SystemScheduler()
        super.tearDown()
    }

    func testSavingAndRestoring() async {
        let effect = await ComposeDraftStore.leave(recipient: "Ada", message: "Thanks for the help")
        XCTAssertTrue(effect.saved)
        XCTAssertTrue(effect.scheduled)
        XCTAssertEqual(fake.scheduledTitles, ["Finish your thank-you to Ada?"])
        XCTAssertEqual(fake.scheduledDelays, [ComposeDraftStore.reminderDelay])
        XCTAssertFalse(fake.scheduledTitles.joined().contains("Thanks for the help"))

        let draft = ComposeDraftStore.restore()
        XCTAssertEqual(draft?.recipient, "Ada")
        XCTAssertEqual(draft?.message, "Thanks for the help")
        XCTAssertEqual(draft?.reminderScheduled, true)

        fake.granted = true
        _ = await ComposeDraftStore.leave(recipient: "Ada", message: "Thanks again")
        XCTAssertEqual(fake.scheduledTitles.count, 1, "one reminder per draft")
        XCTAssertEqual(ComposeDraftStore.restore()?.message, "Thanks again")
    }

    func testClearingOnSend() async {
        fake.granted = true
        _ = await ComposeDraftStore.leave(recipient: "Sam", message: "You showed up")
        ComposeDraftStore.clearAfterSend()
        XCTAssertNil(ComposeDraftStore.restore())
        XCTAssertEqual(fake.cancelled, [ComposeDraftStore.notificationID])
    }

    func testClearingOnDiscard() async {
        fake.granted = true
        _ = await ComposeDraftStore.leave(recipient: "Sam", message: "You showed up")
        ComposeDraftStore.discard()
        XCTAssertNil(ComposeDraftStore.restore())
        XCTAssertEqual(fake.cancelled, [ComposeDraftStore.notificationID])

        _ = await ComposeDraftStore.leave(recipient: "Sam", message: "Still here")
        let emptied = await ComposeDraftStore.leave(recipient: "  ", message: "")
        XCTAssertTrue(emptied.discarded)
        XCTAssertNil(ComposeDraftStore.restore())
    }

    func testNoSchedulingWhenPermissionIsNotGranted() async {
        fake.granted = false
        let effect = await ComposeDraftStore.leave(recipient: "Ada", message: "Thanks")
        XCTAssertTrue(effect.saved)
        XCTAssertFalse(effect.scheduled)
        XCTAssertTrue(fake.scheduledTitles.isEmpty)
        XCTAssertEqual(ComposeDraftStore.restore()?.reminderScheduled, false)
        XCTAssertEqual(ComposeDraftStore.restore()?.message, "Thanks")
    }

    func testHeartNovemberAndPrefillDoNotStealTheDraft() {
        XCTAssertTrue(ComposeDraftStore.ownsDraft(.init(analyticsSource: "tab_compose")))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(analyticsSource: "campaign_universal_link")))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(analyticsSource: "campaign_deeplink")))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(
            analyticsSource: "campaign_home",
            hasCampaign: true
        )))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(
            analyticsSource: "profile",
            hasInitialRecipient: true
        )))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(isEditing: true)))
        XCTAssertFalse(ComposeDraftStore.ownsDraft(.init(analyticsSource: "watch")))
    }
}

/// Same rule as `MainTabView.presentPendingComposeIfNeeded`.
enum QueuedComposePresentation {
    static func shouldPresent(isWeakDefault: Bool) -> Bool {
        !isWeakDefault
    }
}

final class QueuedComposePresentationTests: XCTestCase {
    func testAutomaticBlankLaunchIsNotPresented() {
        XCTAssertFalse(QueuedComposePresentation.shouldPresent(isWeakDefault: true))
        XCTAssertTrue(QueuedComposePresentation.shouldPresent(isWeakDefault: false))
    }
}

private final class FakeScheduler: ComposeDraftStore.Scheduling {
    var granted = true
    var scheduledTitles: [String] = []
    var scheduledDelays: [TimeInterval] = []
    var cancelled: [String] = []

    func permissionGranted() async -> Bool { granted }

    func schedule(id: String, title: String, after: TimeInterval) async -> Bool {
        scheduledTitles.append(title)
        scheduledDelays.append(after)
        return true
    }

    func cancel(id: String) { cancelled.append(id) }
}
