import XCTest
@testable import OpenThanks

final class GuestBrowseTests: XCTestCase {
    func testRootUsesGuestShellAfterOnboarding() throws {
        let source = try readSource("OpenThanks/OpenThanksApp.swift")
        XCTAssertTrue(source.contains("GuestBrowseShell()"))
        XCTAssertFalse(source.contains("if hasSeenOnboarding {\n                        WelcomeView()"))
    }

    func testOnboardingCtaInvitesExplore() throws {
        let source = try readSource("OpenThanks/Views/Auth/OnboardingView.swift")
        XCTAssertTrue(source.contains("See what’s shared"))
    }

    func testFeedSupportsGuestWorldBrowse() throws {
        let source = try readSource("OpenThanks/Views/Feed/FeedView.swift")
        XCTAssertTrue(source.contains("isGuestMode"))
        XCTAssertTrue(source.contains("onRequestSignIn"))
        XCTAssertTrue(source.contains("GratitudeService.worldFeed()"))
        XCTAssertTrue(source.contains("Browse real thank-yous"))
    }

    func testClaimPromptsSignInSheet() throws {
        let source = try readSource("OpenThanks/Views/Claim/ClaimAppreciationView.swift")
        XCTAssertTrue(source.contains("Sign in to keep"))
        XCTAssertTrue(source.contains("GuestSignInReason.claim"))
    }

    func testComposeSavePromptsGuestSignIn() throws {
        let source = try readSource("OpenThanks/Views/Compose/ComposeView.swift")
        XCTAssertTrue(source.contains("promptGuestSignInToSave"))
        XCTAssertTrue(source.contains("guest_resume"))
        XCTAssertTrue(source.contains("Continue to save"))
    }

    func testProfileRippleWorksForGuests() throws {
        let source = try readSource("OpenThanks/Views/Profile/ProfileView.swift")
        XCTAssertTrue(source.contains("auth.userId == nil"))
        XCTAssertTrue(source.contains("composeAnalyticsSource = \"ripple_tab\""))
    }

    private func readSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
