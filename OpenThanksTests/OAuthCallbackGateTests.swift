import XCTest
#if canImport(OAuthCallbackGate)
@testable import OAuthCallbackGate
#else
@testable import OpenThanks
#endif

final class OAuthCallbackGateTests: XCTestCase {
    private let callback = URL(string: "openthanks://auth-callback?code=pkce-code")!
    private let fragmentCallback = URL(string: "openthanks://auth-callback#access_token=abc")!
    private let compose = URL(string: "openthanks://compose")!
    private let httpsLander = URL(string: "https://openthanks.com/auth/mobile?code=pkce-code")!

    func testIdleGateForwardsTheAuthCallback() {
        let gate = OAuthCallbackGate()
        XCTAssertTrue(gate.shouldForward(callback))
        XCTAssertTrue(gate.shouldForward(fragmentCallback))
        XCTAssertTrue(gate.shouldForward(compose))
        XCTAssertTrue(gate.shouldForward(httpsLander))
    }

    func testInFlightSignInDoesNotForwardTheSameCallback() async throws {
        let gate = OAuthCallbackGate()
        try await gate.owningAuthCallback {
            XCTAssertFalse(gate.shouldForward(callback))
            XCTAssertFalse(gate.shouldForward(fragmentCallback))
            XCTAssertFalse(
                gate.shouldForward(URL(string: "OpenThanks://Auth-Callback?code=again")!)
            )
            // Widget and https links are not the PKCE callback.
            XCTAssertTrue(gate.shouldForward(compose))
            XCTAssertTrue(gate.shouldForward(httpsLander))
            XCTAssertTrue(gate.shouldForward(URL(string: "openthanks://claim/abc")!))
        }
        XCTAssertTrue(gate.shouldForward(callback))
    }

    func testFailedSignInReleasesTheCallback() async {
        let gate = OAuthCallbackGate()
        do {
            try await gate.owningAuthCallback {
                XCTAssertFalse(gate.shouldForward(callback))
                throw SampleFailure()
            }
            XCTFail("expected throw")
        } catch is SampleFailure {
            XCTAssertTrue(gate.shouldForward(callback))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testNestedOwnershipWaitsForTheOuterExchange() {
        let gate = OAuthCallbackGate()
        gate.begin()
        gate.begin()
        XCTAssertFalse(gate.shouldForward(callback))
        gate.end()
        XCTAssertFalse(gate.shouldForward(callback))
        gate.end()
        XCTAssertTrue(gate.shouldForward(callback))
        // Extra end must not stick the gate closed.
        gate.end()
        XCTAssertTrue(gate.shouldForward(callback))
    }

    func testAuthCallbackMatchIgnoresOtherSchemes() {
        XCTAssertTrue(OAuthCallbackGate.isAuthCallback(callback))
        XCTAssertTrue(OAuthCallbackGate.isAuthCallback(
            URL(string: "openthanks://login/auth-callback?code=1")!
        ))
        XCTAssertFalse(OAuthCallbackGate.isAuthCallback(compose))
        XCTAssertFalse(OAuthCallbackGate.isAuthCallback(httpsLander))
    }

    func testSignInHoldsTheGateThroughTheTokenExchange() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let body = try functionBody("signInWithOAuth", in: source)
        XCTAssertTrue(body.contains("oauthCallbackGate.owningAuthCallback"))
        guard let ownStart = body.range(of: "oauthCallbackGate.owningAuthCallback"),
              let exchange = body.range(of: "supabase.auth.signInWithOAuth(")
        else {
            XCTFail("missing gate or exchange")
            return
        }
        XCTAssertLessThan(ownStart.lowerBound, exchange.lowerBound)
        let afterExchange = body[exchange.upperBound...]
        XCTAssertTrue(afterExchange.contains("handleAuthSuccess(method: method)"))
        XCTAssertTrue(afterExchange.contains("recordSignInFailure(method: method, error: message)"))

        let deepLink = try functionBody("handleDeepLink", in: source)
        guard let forward = deepLink.range(of: "oauthCallbackGate.shouldForward(url)"),
              let handle = deepLink.range(of: "supabase.auth.handle(url)")
        else {
            XCTFail("handleDeepLink must consult the gate before exchanging")
            return
        }
        XCTAssertLessThan(forward.lowerBound, handle.lowerBound)
        XCTAssertTrue(deepLink.contains("else { return }"))
    }
}

private struct SampleFailure: Error {}

private func repoSource(_ relative: String) throws -> String {
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
        throw MissingFunction(name: name)
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
    throw MissingFunction(name: name)
}

private struct MissingFunction: Error, CustomStringConvertible {
    let name: String
    var description: String { "Missing function \(name)" }
}
