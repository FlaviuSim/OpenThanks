import XCTest
#if canImport(PasskeySignIn)
@testable import PasskeySignIn
#else
@testable import OpenThanks
#endif
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

final class PasskeySignInTests: XCTestCase {
    private let reviewErrorText =
        "The operation couldn’t be completed. (com.apple.AuthenticationServices.AuthorizationError error 1004.)"

    func testError1004StaysOnSignInWithTheInlineMessage() {
        let error = authorizationError(code: PasskeySignInFailure.failedCode, description: reviewErrorText)
        XCTAssertFalse(PasskeySignInFailure.isCancellation(error))
        XCTAssertEqual(
            PasskeySignInFailure.screen(after: error),
            .stayShowing("No passkey found for this account. Try Apple, Google or email.")
        )
    }

    func testError1004IsNotSilentWhenTheDescriptionMentionsCancel() {
        let error = authorizationError(
            code: PasskeySignInFailure.failedCode,
            description: "The user canceled the request (error 1004)."
        )
        XCTAssertEqual(
            PasskeySignInFailure.screen(after: error),
            .stayShowing(PasskeySignInFailure.noPasskeyMessage)
        )
    }

    func testBareAuthorizationFailure1004UsesTheSameMessage() {
        let error = NSError(
            domain: PasskeySignInFailure.authorizationErrorDomain,
            code: PasskeySignInFailure.failedCode
        )
        XCTAssertEqual(
            PasskeySignInFailure.screen(after: error),
            .stayShowing(PasskeySignInFailure.noPasskeyMessage)
        )
    }

    func testOtherAuthorizationFailuresStayOnScreenWithTheMessage() {
        for code in [1000, 1002, 1003, 1005] {
            let error = authorizationError(code: code, description: "Authorization failed (\(code)).")
            XCTAssertEqual(
                PasskeySignInFailure.screen(after: error),
                .stayShowing(PasskeySignInFailure.noPasskeyMessage),
                "code \(code)"
            )
        }
    }

    func testNotAllowedStillCountsAsASilentDismissal() {
        let error = NSError(
            domain: "OpenThanks.Passkey",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The operation is not allowed."]
        )
        XCTAssertTrue(PasskeySignInFailure.isCancellation(error))
        XCTAssertEqual(PasskeySignInFailure.screen(after: error), .staySilent)
    }

    func testDismissingThePasskeySheetStaysSilent() {
        let canceled = authorizationError(code: PasskeySignInFailure.canceledCode, description: "Canceled")
        XCTAssertTrue(PasskeySignInFailure.isCancellation(canceled))
        XCTAssertEqual(PasskeySignInFailure.screen(after: canceled), .staySilent)

        let dismissed = NSError(
            domain: "OpenThanks.Passkey",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The operation was canceled."]
        )
        XCTAssertEqual(PasskeySignInFailure.screen(after: dismissed), .staySilent)
    }

    func testPasskeySignInCatchStaysSignedOutAndShowsTheMessage() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let body = try functionBody("signInWithPasskey", in: source)
        let parts = body.components(separatedBy: "} catch {")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[0].contains("handleAuthSuccess(method: \"passkey\")"))
        let catchBody = parts[1]
        XCTAssertTrue(catchBody.contains("PasskeySignInFailure.screen(after: error)"))
        XCTAssertTrue(catchBody.contains("errorMessage = message"))
        XCTAssertTrue(catchBody.contains("return false"))
        XCTAssertFalse(catchBody.contains("handleAuthSuccess"))
        XCTAssertFalse(catchBody.contains("signedIn"))
    }

    func testWelcomeScreenStillShowsTheInlineErrorAndPasskeyStaysPut() throws {
        let source = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")
        XCTAssertTrue(source.contains("if let error = auth.errorMessage"))
        let passkey = try functionBody("signInWithPasskey", in: source)
        XCTAssertTrue(passkey.contains("auth.signInWithPasskey()"))
        XCTAssertFalse(passkey.contains("dismiss"))
        XCTAssertFalse(passkey.contains("signedIn"))
    }

    func testOtherSignInMethodsStillReachTheirOwnProviders() throws {
        let source = try repoSource("OpenThanks/Services/AuthService.swift")
        let welcome = try repoSource("OpenThanks/Views/Auth/WelcomeView.swift")

        let google = try functionBody("signInWithGoogle", in: source)
        XCTAssertTrue(google.contains("signInWithOAuth(provider: .google, method: \"google\")"))

        let linkedin = try functionBody("signInWithLinkedIn", in: source)
        XCTAssertTrue(linkedin.contains("signInWithOAuth(provider: .linkedinOIDC, method: \"linkedin\")"))

        let apple = try functionBody("signInWithApple", in: source)
        XCTAssertTrue(apple.contains("signInWithIdToken"))
        XCTAssertTrue(apple.contains("friendlyAuthError"))
        XCTAssertTrue(apple.contains("handleAuthSuccess(method: \"apple\")"))

        let email = try functionBody("sendEmailCode", in: source)
        XCTAssertTrue(email.contains("signInWithOTP(email:"))
        XCTAssertTrue(email.contains("signInTestAccount()"))
        let verifyEmail = try functionBody("verifyEmailCode", in: source)
        XCTAssertTrue(verifyEmail.contains("verifyOTP(email:"))
        XCTAssertTrue(verifyEmail.contains("handleAuthSuccess(method: \"email\")"))

        let phone = try functionBody("sendPhoneCode", in: source)
        XCTAssertTrue(phone.contains("signInWithOTP(phone:"))
        let verifyPhone = try functionBody("verifyPhoneCode", in: source)
        XCTAssertTrue(verifyPhone.contains("verifyOTP(phone:"))
        XCTAssertTrue(verifyPhone.contains("handleAuthSuccess(method: \"phone\")"))

        let oauth = try functionBody("signInWithOAuth", in: source)
        XCTAssertTrue(oauth.contains("signInWithOAuth"))
        XCTAssertTrue(oauth.contains("handleAuthSuccess(method: method)"))
        XCTAssertTrue(oauth.contains("errorMessage = message"))

        for body in [google, linkedin, apple, email, verifyEmail, phone, verifyPhone, oauth] {
            XCTAssertFalse(body.contains("PasskeySignInFailure"))
            XCTAssertFalse(body.contains(PasskeySignInFailure.noPasskeyMessage))
        }

        XCTAssertTrue(welcome.contains("Continue with Apple"))
        XCTAssertTrue(welcome.contains("Continue with Google"))
        XCTAssertTrue(welcome.contains("Continue with LinkedIn"))
        XCTAssertTrue(welcome.contains("Continue with Email"))
        XCTAssertTrue(welcome.contains("Continue with Phone"))
        XCTAssertTrue(welcome.contains("Continue with Passkey"))
        XCTAssertTrue(welcome.contains("auth.signInWithGoogle()"))
        XCTAssertTrue(welcome.contains("auth.signInWithLinkedIn()"))
        XCTAssertTrue(welcome.contains("auth.signInWithApple("))
        XCTAssertTrue(welcome.contains("showEmailSheet = true"))
        XCTAssertTrue(welcome.contains("showPhoneSheet = true"))
    }

    func testPasskeyFailureCopyIsNotAppliedToOtherMethods() {
        let failure = authorizationError(code: PasskeySignInFailure.failedCode, description: reviewErrorText)
        for method in ["apple", "google", "linkedin", "email", "phone"] {
            XCTAssertNil(passkeyBanner(method: method, error: failure), method)
        }
        XCTAssertEqual(
            passkeyBanner(method: "passkey", error: failure),
            PasskeySignInFailure.noPasskeyMessage
        )
    }

    #if canImport(AuthenticationServices)
    func testFailureCodesMatchAuthenticationServices() {
        XCTAssertEqual(PasskeySignInFailure.authorizationErrorDomain, ASAuthorizationError.errorDomain)
        XCTAssertEqual(PasskeySignInFailure.canceledCode, ASAuthorizationError.canceled.rawValue)
        XCTAssertEqual(PasskeySignInFailure.failedCode, ASAuthorizationError.failed.rawValue)
    }
    #endif

    private func passkeyBanner(method: String, error: Error) -> String? {
        guard method == "passkey" else { return nil }
        guard case .stayShowing(let message) = PasskeySignInFailure.screen(after: error) else {
            return nil
        }
        return message
    }

    private func authorizationError(code: Int, description: String) -> NSError {
        NSError(
            domain: PasskeySignInFailure.authorizationErrorDomain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

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
}

private struct MissingFunction: Error, CustomStringConvertible {
    let name: String
    var description: String { "Missing function \(name)" }
}
