import XCTest
#if canImport(ReviewPrompt)
@testable import ReviewPrompt
#else
@testable import OpenThanks
#endif

final class AppStoreReviewPromptTests: XCTestCase {
    private final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func record() {
            lock.lock()
            value += 1
            lock.unlock()
        }
        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private var suiteName = ""

    override func setUp() async throws {
        suiteName = "AppStoreReviewPromptTests.\(UUID().uuidString)"
        let name = suiteName
        await MainActor.run {
            let defaults = UserDefaults(suiteName: name)!
            defaults.removePersistentDomain(forName: name)
            AppStoreReviewPrompt.cancelPending()
            AppStoreReviewPrompt.defaults = defaults
            AppStoreReviewPrompt.reviewHook = nil
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            AppStoreReviewPrompt.cancelPending()
            AppStoreReviewPrompt.reviewHook = nil
            AppStoreReviewPrompt.defaults = .standard
        }
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func testAcceptDoesNotRequestReview() {
        XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(
            .acceptedAppreciation, alreadyRequested: false
        ))
        XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(
            .postAcceptMoment, alreadyRequested: false
        ))
    }

    func testFirstSendIsTheOnlyMomentThatRequests() {
        XCTAssertTrue(AppStoreReviewPrompt.shouldRequest(
            .successfulSend(count: 1), alreadyRequested: false
        ))
        XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(
            .successfulSend(count: 0), alreadyRequested: false
        ))
        XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(
            .successfulSend(count: 2), alreadyRequested: false
        ))
        XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(
            .successfulSend(count: 5), alreadyRequested: false
        ))
    }

    func testOnceOnlyStillBlocksEveryMoment() {
        for event: AppStoreReviewPrompt.Event in [
            .acceptedAppreciation,
            .postAcceptMoment,
            .successfulSend(count: 1),
        ] {
            XCTAssertFalse(AppStoreReviewPrompt.shouldRequest(event, alreadyRequested: true))
        }
    }

    /// People who already got the accept-time prompt keep the same flag.
    func testRequestedKeyIsUnchanged() {
        XCTAssertEqual(
            AppStoreReviewPrompt.requestedKey,
            "appStoreReviewRequestedAfterReceive.v1"
        )
    }

    func testSchedulingAcceptDoesNotPresent() async {
        let calls = Calls()
        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.acceptedAppreciation, delaySeconds: 0)
            AppStoreReviewPrompt.schedule(.postAcceptMoment, delaySeconds: 0)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.count, 0)
        XCTAssertFalse(AppStoreReviewPrompt.hasRequested)
    }

    func testFirstSuccessfulSendPresentsOnce() async {
        let calls = Calls()
        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
        }
        await waitUntil { calls.count == 1 }
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(AppStoreReviewPrompt.hasRequested)

        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
            AppStoreReviewPrompt.schedule(.successfulSend(count: 2), delaySeconds: 0)
            AppStoreReviewPrompt.schedule(.acceptedAppreciation, delaySeconds: 0)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.count, 1)
    }

    func testAlreadyRequestedFlagSkipsTheFirstSend() async {
        AppStoreReviewPrompt.defaults.set(true, forKey: AppStoreReviewPrompt.requestedKey)
        let calls = Calls()
        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.count, 0)
        XCTAssertTrue(AppStoreReviewPrompt.hasRequested)
    }

    func testLaterSendsDoNotPresent() async {
        let calls = Calls()
        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 0), delaySeconds: 0)
            AppStoreReviewPrompt.schedule(.successfulSend(count: 2), delaySeconds: 0)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(calls.count, 0)
        XCTAssertFalse(AppStoreReviewPrompt.hasRequested)
    }

    /// A later schedule still replaces the pending delay, and only one request fires.
    func testPendingDelayIsReplaced() async {
        let calls = Calls()
        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0.35)
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
        }
        await waitUntil { calls.count == 1 }
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(calls.count, 1)
        XCTAssertTrue(AppStoreReviewPrompt.hasRequested)
    }

    /// No scene still leaves the one request unused, same as before.
    func testFailedPresentationDoesNotConsumeTheRequest() async {
        let calls = Calls()
        await MainActor.run {
            AppStoreReviewPrompt.reviewHook = {
                calls.record()
                return false
            }
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
        }
        await waitUntil { calls.count == 1 }
        XCTAssertFalse(AppStoreReviewPrompt.hasRequested)

        await arm(calls)
        await MainActor.run {
            AppStoreReviewPrompt.schedule(.successfulSend(count: 1), delaySeconds: 0)
        }
        await waitUntil { calls.count == 2 }
        XCTAssertTrue(AppStoreReviewPrompt.hasRequested)
    }

    @MainActor
    private func arm(_ calls: Calls) {
        AppStoreReviewPrompt.reviewHook = {
            calls.record()
            return true
        }
    }

    private func waitUntil(
        _ condition: @Sendable () -> Bool,
        timeout: TimeInterval = 2
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("timed out waiting for the review prompt")
    }
}
