import Foundation

/// What the sign-in screen does after a passkey ceremony error.
///
/// The system reports a missing passkey — including on a fresh App Review
/// device — as `ASAuthorizationError.failed` (code 1004). That stays on the
/// sign-in screen with ``noPasskeyMessage``. Dismissing the system sheet
/// stays on the screen with no message.
enum PasskeySignInFailure {
    /// `ASAuthorizationError.errorDomain`. A string so this file does not
    /// import AuthenticationServices and can be tested on Linux.
    static let authorizationErrorDomain = "com.apple.AuthenticationServices.AuthorizationError"

    /// `ASAuthorizationError.canceled`
    static let canceledCode = 1001
    /// `ASAuthorizationError.failed`
    static let failedCode = 1004

    static let noPasskeyMessage = "No passkey found for this account. Try Apple, Google or email."

    enum Screen: Equatable {
        /// User dismissed the system sheet. Leave the sign-in screen as it is.
        case staySilent
        /// Show `message` under the sign-in buttons. Do not leave the screen.
        case stayShowing(String)
    }

    static func screen(after error: Error) -> Screen {
        if isCancellation(error) { return .staySilent }
        return .stayShowing(noPasskeyMessage)
    }

    /// True only when the person dismissed the sheet.
    /// Code 1004 is never a dismissal, even if the description mentions cancel.
    static func isCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == authorizationErrorDomain {
            if ns.code == failedCode { return false }
            if ns.code == canceledCode { return true }
        }
        let text = ns.localizedDescription.lowercased()
        if text.contains("error 1004") { return false }
        return text.contains("cancel") || text.contains("not allowed") || text.contains("abort")
    }
}
