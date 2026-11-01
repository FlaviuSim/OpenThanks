import XCTest

/// Optional network e2e against the App Store review account.
/// Skips when `RUN_NETWORK_E2E` is not set so CI / local default stays offline-fast.
final class DemoLoginUITests: XCTestCase {
    func testDemoAccountReachesHomeTabs() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_E2E"] == "1",
            "Set RUN_NETWORK_E2E=1 to exercise the live review-account login."
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-demo-login",
        ]
        app.launch()

        let home = app.buttons["tab.home"]
        let compose = app.buttons["tab.compose"]
        let reachedHome = home.waitForExistence(timeout: 45) || compose.waitForExistence(timeout: 1)
        XCTAssertTrue(reachedHome, "Demo login should land on the main tab bar")
    }
}
