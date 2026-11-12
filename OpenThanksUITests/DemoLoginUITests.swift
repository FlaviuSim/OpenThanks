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

    /// Home people search must scroll through an overflowing list, including after the keyboard drops.
    func testHomeSearchOverflowResultsScrollAndOpen() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_E2E"] == "1",
            "Set RUN_NETWORK_E2E=1 to scroll an overflowing Home people search."
        )

        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-demo-login",
            "-ui-testing-search-overflow",
        ]
        app.launch()

        dismissBlockingPrompts(app)

        let field = app.textFields["Search for someone to thank"]
        XCTAssertTrue(field.waitForExistence(timeout: 30), "Home search field should be on screen")
        field.tap()
        field.typeText("ov")

        let first = app.staticTexts["Overflow Person 01"]
        XCTAssertTrue(first.waitForExistence(timeout: 10), "Search should show the overflow fixture")
        saveShot(app, name: "results-initial")

        let last = app.staticTexts["Overflow Person 24"]
        XCTAssertTrue(last.waitForExistence(timeout: 5), "The last fixture person should be in the hierarchy")

        let fieldBottom = field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
        for _ in 0..<20 {
            if last.isHittable { break }
            let start = fieldBottom.withOffset(CGVector(dx: 0, dy: 70))
            let end = fieldBottom.withOffset(CGVector(dx: 0, dy: 16))
            start.press(forDuration: 0.01, thenDragTo: end)
        }
        saveShot(app, name: "results-after-scroll")

        XCTAssertTrue(last.isHittable, "The last search result should scroll on screen and stay tappable")
        last.tap()

        let opened = app.staticTexts["Overflow Person 24"].waitForExistence(timeout: 8)
            || app.navigationBars["Overflow Person 24"].waitForExistence(timeout: 2)
        saveShot(app, name: "result-opened")
        XCTAssertTrue(opened, "Tapping the last result should open that profile")
    }

    private func dismissBlockingPrompts(_ app: XCUIApplication) {
        for _ in 0..<4 {
            let notNow = app.buttons["Not now"]
            if notNow.waitForExistence(timeout: 4), notNow.isHittable {
                notNow.tap()
                continue
            }
            let close = app.buttons["Close"]
            if close.exists, close.isHittable, !app.textFields["Search for someone to thank"].exists {
                close.tap()
                continue
            }
            break
        }
    }

    private func saveShot(_ app: XCUIApplication, name: String) {
        let envPrefix = ProcessInfo.processInfo.environment["SHOT_PREFIX"]
        let width = app.windows.firstMatch.frame.width
        let prefix = envPrefix ?? (width > 700 ? "ipad" : "iphone")
        let url = URL(fileURLWithPath: "/tmp/ot-shots/\(prefix)-\(name).png")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? app.screenshot().pngRepresentation.write(to: url)
    }
}
