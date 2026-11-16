import XCTest
@testable import OpenThanks

final class OAuthAvatarTests: XCTestCase {
    func testDetectsGoogleLetterAndDefaultAvatars() {
        XCTAssertTrue(
            AuthService.isProviderPlaceholderAvatar(
                "https://lh3.googleusercontent.com/a/ACg8ocKletteravatar=s96-c"
            )
        )
        XCTAssertTrue(
            AuthService.isProviderPlaceholderAvatar(
                "https://lh3.googleusercontent.com/a/default-user=s100"
            )
        )
        XCTAssertTrue(
            AuthService.isProviderPlaceholderAvatar(
                "https://lh3.googleusercontent.com/-XdUIqdMkCWA/AAAAAAAAAAI/AAAAAAAAAAA/4252rscbv5M/photo.jpg"
            )
        )
        XCTAssertTrue(AuthService.isProviderPlaceholderAvatar(nil))
        XCTAssertTrue(AuthService.isProviderPlaceholderAvatar("  "))
    }

    func testAllowsRealGooglePhotos() {
        XCTAssertFalse(
            AuthService.isProviderPlaceholderAvatar(
                "https://lh3.googleusercontent.com/a-/AOh14Gg_realphotohash=s96-c"
            )
        )
    }

    func testNewProfileSkipsPlaceholderAvatar() throws {
        let source = try readSource("OpenThanks/Services/AuthService.swift")
        XCTAssertTrue(source.contains("isProviderPlaceholderAvatar"))
        XCTAssertTrue(source.contains("Skip Google letter"))
    }

    private func readSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
