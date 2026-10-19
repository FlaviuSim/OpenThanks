import XCTest

/// Launch metrics for the 1.5 ship gate. Prefer running on a physical device.
final class LaunchPerformanceUITests: XCTestCase {
    func testColdLaunchPerformance() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = [
                "-ui-testing",
                "-ui-testing-signed-out",
            ]
            app.launch()
        }
    }
}
