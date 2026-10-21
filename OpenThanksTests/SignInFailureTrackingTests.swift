import XCTest
#if canImport(PasskeySignIn)
@testable import PasskeySignIn
#else
@testable import OpenThanks
#endif

/// Source-level checks for silent sign-in analytics. AuthService and SwiftUI
/// cannot be executed on Linux; these tests follow the call into
/// `Analytics.signInFailed`, which is what queues `sign_in_failed`.
final class SignInFailureTrackingTests: XCTestCase {
    func testOAuthCancelRecordsFailureAndLeavesTheBannerUnset() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let oauth = try functionBody("signInWithOAuth", in: source)
        let cancel = try braceBlock(after: "if Self.isOAuthCancellation(error)", in: oauth)
        XCTAssertTrue(cancel.contains("recordSignInFailure(method: method, error: \"canceled\")"))
        XCTAssertTrue(cancel.contains("return false"))
        XCTAssertFalse(cancel.contains("errorMessage"))
        XCTAssertTrue(try functionBody("recordSignInFailure", in: source)
            .contains("Analytics.signInFailed(method: method, error: error)"))
        XCTAssertTrue(try functionBody("signInFailed", in: try repoSource("OpenThanks/Services/Analytics.swift"))
            .contains("capture(\"sign_in_failed\""))
    }

    func testOAuthFailuresOtherThanCancelStillShowTheExistingBanner() throws {
        let oauth = try functionBody(
            "signInWithOAuth",
            in: try repoSource("OpenThanks/Services/AuthService.swift")
        )
        let afterCancel = oauth.components(separatedBy: "isOAuthCancellation(error)").last ?? ""
        XCTAssertTrue(afterCancel.contains("errorMessage = message"))
        XCTAssertTrue(afterCancel.contains("recordSignInFailure(method: method, error: message)"))
    }

    func testLinkingGoogleCancelDoesNotEmitASignInFailure() throws {
        let link = try functionBody(
            "linkGoogleIdentity",
            in: try repoSource("OpenThanks/Services/AuthService.swift")
        )
        let cancel = try braceBlock(after: "if Self.isOAuthCancellation(error)", in: link)
        XCTAssertEqual(cancel.trimmingCharacters(in: .whitespacesAndNewlines), "return false")
        XCTAssertFalse(link.contains("recordSignInFailure"))
        XCTAssertFalse(link.contains("signInFailed"))
    }

    func testAppleCancelRecordsFailureWithoutABanner() throws {
        let welcome = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        let apple = try functionBody("handleAppleResult", in: welcome)
        let cancel = try braceBlock(after: "authError.code == .canceled", in: apple)
        XCTAssertTrue(cancel.contains("Analytics.signInFailed(method: \"apple\", error: \"canceled\")"))
        XCTAssertTrue(cancel.contains("return"))
        XCTAssertFalse(cancel.contains("errorMessage"))
        XCTAssertFalse(cancel.contains("oauthBusy"))
    }

    func testAppleUnknownStaysSilentWithNoEvent() throws {
        let apple = try functionBody(
            "handleAppleResult",
            in: try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        )
        let unknown = try braceBlock(after: "authError.code == .unknown", in: apple)
        XCTAssertEqual(unknown.trimmingCharacters(in: .whitespacesAndNewlines), "return")
        XCTAssertFalse(unknown.contains("signInFailed"))
        XCTAssertFalse(unknown.contains("errorMessage"))
        XCTAssertFalse(unknown.contains("oauthBusy"))
    }

    func testPasskeySilentCancelRecordsFailureWithoutABanner() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let passkey = try functionBody("signInWithPasskey", in: source)
        let silent = slice(from: "case .staySilent:", to: "case .stayShowing", in: passkey)
        XCTAssertTrue(silent.contains("recordSignInFailure(method: \"passkey\", error: \"canceled\")"))
        XCTAssertTrue(silent.contains("return false"))
        XCTAssertFalse(silent.contains("errorMessage"))
    }

    func testPasskeyMissingCredentialStillShowsTheSameBanner() throws {
        let passkey = try functionBody(
            "signInWithPasskey",
            in: try repoSource("OpenThanks/Services/AuthService.swift")
        )
        let showing = slice(from: "case .stayShowing(let message):", to: "}", in: passkey)
        XCTAssertTrue(showing.contains("errorMessage = message"))
        XCTAssertTrue(showing.contains("recordSignInFailure(method: \"passkey\", error: error.localizedDescription)"))
        XCTAssertFalse(showing.contains("\"canceled\""))
    }

    func testNotAllowedClassificationIsUnchangedInTheShippingFile() throws {
        let tested = try functionBody(
            "isCancellation",
            in: try repoSource("OpenThanksTests/Sources/PasskeySignIn/PasskeySignIn.swift")
        )
        let shipping = try functionBody(
            "isCancellation",
            in: try repoSource("OpenThanks/Services/PasskeySignIn.swift")
        )
        XCTAssertEqual(tested, shipping)
        XCTAssertTrue(shipping.contains("text.contains(\"not allowed\")"))
        let notAllowed = NSError(
            domain: "OpenThanks.Passkey",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The operation is not allowed."]
        )
        XCTAssertEqual(PasskeySignInFailure.screen(after: notAllowed), .staySilent)
    }

    func testOTPAbandonAfterCodeSentRecordsFailureWithoutABanner() throws {
        let welcome = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        XCTAssertTrue(welcome.contains(".onDisappear { trackAbandonedOTPIfNeeded() }"))
        let track = try functionBody("trackAbandonedOTPIfNeeded", in: welcome)
        XCTAssertTrue(track.contains("guard codeSent, !completedSignIn, !didTrackOTPAbandon else { return }"))
        XCTAssertTrue(track.contains("if case .signedIn = auth.state { return }"))
        XCTAssertTrue(track.contains("method: mode == .email ? \"email\" : \"phone\""))
        XCTAssertTrue(track.contains("error: \"abandoned\""))
        XCTAssertTrue(track.contains("Analytics.signInFailed("))
        XCTAssertFalse(track.contains("errorMessage"))
        XCTAssertFalse(track.contains("signInMethodTapped"))
        let submit = try functionBody("submit", in: welcome)
        XCTAssertTrue(submit.contains("completedSignIn = true"))
        XCTAssertTrue(submit.contains("dismiss()"))
    }

    func testOTPSheetOpenStillCountsAsATapAndDoesNotTrackAbandonEarly() throws {
        let welcome = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        let emailTap = slice(
            from: "Analytics.signInMethodTapped(\"email\")",
            to: "showEmailSheet = true",
            in: welcome
        )
        let phoneTap = slice(
            from: "Analytics.signInMethodTapped(\"phone\")",
            to: "showPhoneSheet = true",
            in: welcome
        )
        XCTAssertFalse(emailTap.contains("signInFailed"))
        XCTAssertFalse(phoneTap.contains("signInFailed"))
        XCTAssertTrue(welcome.contains("Button(\"Cancel\") { dismiss() }"))
        XCTAssertFalse(welcome.contains("Text(\"abandoned\")"))
        XCTAssertFalse(welcome.contains("Text(\"canceled\")"))
    }

    func testSignInScreenCopyAndBusyStateAreUnchanged() throws {
        let welcome = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        for label in [
            "Opening Google…",
            "Continue with Google",
            "Opening LinkedIn…",
            "Continue with LinkedIn",
            "Continue with Email",
            "Continue with Phone",
            "Waiting for passkey…",
            "Continue with Passkey",
            "Continue with Apple",
        ] {
            XCTAssertTrue(welcome.contains(label), label)
        }
        XCTAssertTrue(welcome.contains("if let error = auth.errorMessage"))
        let oauth = try functionBody("signInWithOAuth", in: welcome)
        XCTAssertTrue(oauth.contains("guard oauthBusy == nil else { return }"))
        XCTAssertTrue(oauth.contains("oauthBusy = provider"))
        let passkey = try functionBody("signInWithPasskey", in: welcome)
        XCTAssertTrue(passkey.contains("guard oauthBusy == nil else { return }"))
        XCTAssertTrue(passkey.contains("oauthBusy = .passkey"))
        for method in ["google", "linkedin", "passkey", "apple", "email", "phone"] {
            XCTAssertTrue(welcome.contains("Analytics.signInMethodTapped(\"\(method)\")"), method)
        }
        let google = slice(
            from: "Analytics.signInMethodTapped(\"google\")",
            to: "signInWithOAuth(.google)",
            in: welcome
        )
        XCTAssertFalse(google.contains("oauthBusy"))
        let appleFailure = slice(from: "case .failure", to: "case .success", in: welcome)
        XCTAssertFalse(appleFailure.contains("oauthBusy"))
    }

    func testShippedSignInEventNamesAndPropertiesAreUnchanged() throws {
        let analytics = try repoSource("OpenThanks/Services/Analytics.swift")
        let tapped = try functionBody("signInMethodTapped", in: analytics)
        XCTAssertTrue(tapped.contains("capture(\"sign_in_method_tapped\", [\"method\": method])"))
        let failed = try functionBody("signInFailed", in: analytics)
        XCTAssertTrue(failed.contains("capture(\"sign_in_failed\""))
        XCTAssertTrue(failed.contains("\"method\": method"))
        XCTAssertTrue(failed.contains("\"error\": message.isEmpty ? \"unknown\" : message"))
        let signedIn = try functionBody("authSignedIn", in: analytics)
        XCTAssertTrue(signedIn.contains("capture(\"auth_signed_in\", props)"))
        XCTAssertTrue(signedIn.contains("[\"method\": method]"))
    }

    func testMissingSessionAfterProviderSuccessRecordsFailureWithoutABanner() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let success = try functionBody("handleAuthSuccess", in: source)
        let missing = try braceBlock(after: "supabase.auth.session else", in: success)
        XCTAssertTrue(missing.contains("recordSignInFailure(method: method, error: \"no session\")"))
        XCTAssertTrue(missing.contains("return"))
        XCTAssertFalse(missing.contains("errorMessage"))
        XCTAssertFalse(missing.contains("authSignedIn"))
        XCTAssertTrue(success.contains("Analytics.authSignedIn(method: method, isSignup: isSignup)"))
    }

    private func repoSource(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func functionBody(_ name: String, in source: String) throws -> String {
        try braceBlock(after: "func \(name)(", in: source)
    }

    private func braceBlock(after marker: String, in source: String) throws -> String {
        guard let start = source.range(of: marker),
              let brace = source[start.upperBound...].firstIndex(of: "{")
        else {
            throw MissingMarker(name: marker)
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
        throw MissingMarker(name: marker)
    }

    private func slice(from startMarker: String, to endMarker: String, in source: String) -> String {
        guard let start = source.range(of: startMarker) else {
            return ""
        }
        let rest = source[start.upperBound...]
        guard let end = rest.range(of: endMarker) else { return String(rest) }
        return String(rest[..<end.lowerBound])
    }
}

private struct MissingMarker: Error, CustomStringConvertible {
    let name: String
    var description: String { "Missing marker \(name)" }
}
