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

    private func readSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
