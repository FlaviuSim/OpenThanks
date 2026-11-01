import XCTest

/// Signed-out welcome / age-gate flows. Deterministic via `-ui-testing` launch args.
final class WelcomeFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-signed-out",
        ]
        app.launch()
    }

    func testWelcomeShowsSignInOptionsAfterAgeConfirm() {
        XCTAssertTrue(
            app.staticTexts["welcome.title"].waitForExistence(timeout: 10),
            "Welcome should appear when signed out"
        )

        confirmAge()

        let email = firstExisting([
            app.buttons["welcome.email"],
            app.buttons["Continue with Email"],
        ], timeout: 5)
        XCTAssertNotNil(email, "Email sign-in should be visible after age confirm")

        let appleExists = app.descendants(matching: .any)["welcome.apple"].waitForExistence(timeout: 3)
            || app.buttons["Continue with Apple"].waitForExistence(timeout: 1)
        XCTAssertTrue(appleExists, "Sign in with Apple should remain on welcome")
    }

    func testEmailSheetOpensFromWelcome() {
        XCTAssertTrue(
            app.staticTexts["welcome.title"].waitForExistence(timeout: 10)
        )
        confirmAge()

        let email = firstExisting([
            app.buttons["welcome.email"],
            app.buttons["Continue with Email"],
        ], timeout: 5)
        XCTAssertNotNil(email)
        email?.tap()

        // Prefer sheet query — TextField identifiers can lag while the cover animates in.
        let sheetTitle = app.staticTexts["What's your email?"]
        XCTAssertTrue(
            sheetTitle.waitForExistence(timeout: 6)
                || app.textFields["otp.emailField"].waitForExistence(timeout: 1),
            "Email OTP sheet should present"
        )

        let field = firstExisting([
            app.textFields["otp.emailField"],
            app.textFields["you@example.com"],
        ], timeout: 4)
        XCTAssertNotNil(field)
        field?.tap()
        field?.typeText("someone@example.com")

        let submit = firstExisting([
            app.buttons["otp.submit"],
            app.buttons["Continue"],
            app.buttons["Send code"],
        ], timeout: 4)
        XCTAssertNotNil(submit)
    }

    private func confirmAge() {
        let age = firstExisting([
            app.buttons["welcome.ageConfirm"],
            app.descendants(matching: .any)["welcome.ageConfirm"],
            app.buttons["I confirm I am 18 or older"],
        ], timeout: 8)
        XCTAssertNotNil(age, "Age confirmation control should be on welcome")
        age?.tap()
    }

    private func firstExisting(_ queries: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in queries where element.exists {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        for element in queries where element.waitForExistence(timeout: 0.1) {
            return element
        }
        return nil
    }
}
