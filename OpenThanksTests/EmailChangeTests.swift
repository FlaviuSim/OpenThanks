import XCTest
@testable import OpenThanks

final class EmailChangeTests: XCTestCase {
    func testIsValidAccountEmailAcceptsNormalAddresses() {
        XCTAssertTrue(AuthService.isValidAccountEmail("you@example.com"))
        XCTAssertTrue(AuthService.isValidAccountEmail("  You.Name+tag@Example.COM "))
    }

    func testIsValidAccountEmailRejectsJunk() {
        XCTAssertFalse(AuthService.isValidAccountEmail(""))
        XCTAssertFalse(AuthService.isValidAccountEmail("not-an-email"))
        XCTAssertFalse(AuthService.isValidAccountEmail("@missing-local.com"))
        XCTAssertFalse(AuthService.isValidAccountEmail("missing-domain@"))
        XCTAssertFalse(AuthService.isValidAccountEmail("spaces emma@example.com"))
    }

    func testEmailChangeRedirectLandsOnWebConfirm() {
        let url = AuthService.emailChangeRedirectURL
        XCTAssertEqual(url.host, "openthanks.com")
        XCTAssertTrue(url.path.contains("auth/confirm"))
        XCTAssertTrue(url.query?.contains("next=/profile/edit") == true
            || url.query?.contains("next=%2Fprofile%2Fedit") == true)
    }

    func testAuthServiceSendsEmailChangeWithRedirect() throws {
        let source = try readSource("OpenThanks/Services/AuthService.swift")
        let body = try functionBody("sendEmailChangeConfirmation", in: source)
        XCTAssertTrue(body.contains("UserAttributes(email:"))
        XCTAssertTrue(body.contains("redirectTo: Self.emailChangeRedirectURL"))
        XCTAssertTrue(body.contains("isValidAccountEmail"))
    }

    func testLoggingInViewExposesEmailChangeFlow() throws {
        let source = try readSource("OpenThanks/Views/Settings/LoggingInView.swift")
        XCTAssertTrue(source.contains("Send confirmation email"))
        XCTAssertTrue(source.contains("I've confirmed — refresh"))
        XCTAssertTrue(source.contains("sendEmailChangeConfirmation"))
        XCTAssertTrue(source.contains("refreshAfterEmailChangeConfirmation"))
        XCTAssertTrue(source.contains("emailChangePending"))
        XCTAssertTrue(source.contains("both your current address and the new one"))
    }

    // MARK: - Source helpers (same pattern as PasskeySignInTests)

    private func readSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func functionBody(_ name: String, in source: String) throws -> String {
        let marker = "func \(name)("
        guard let start = source.range(of: marker),
              let brace = source[start.upperBound...].firstIndex(of: "{")
        else {
            throw EmailChangeMissingFunction(name: name)
        }
        var depth = 0
        var index = brace
        while index < source.endIndex {
            let character = source[index]
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(source[source.index(after: brace)..<index])
                }
            }
            index = source.index(after: index)
        }
        throw EmailChangeMissingFunction(name: name)
    }
}

private struct EmailChangeMissingFunction: Error, CustomStringConvertible {
    let name: String
    var description: String { "Missing function \(name)" }
}
