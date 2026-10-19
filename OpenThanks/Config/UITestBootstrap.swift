import Foundation
import UIKit

/// Launch-argument hooks for XCUITest. Keeps signed-out / signed-in flows deterministic
/// without shipping a separate test build.
enum UITestBootstrap {
    static let uiTestingArgument = "-ui-testing"
    static let freshInstallArgument = "-ui-testing-fresh"
    static let signedOutArgument = "-ui-testing-signed-out"
    static let demoLoginArgument = "-ui-testing-demo-login"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }

    static var wantsFreshInstall: Bool {
        ProcessInfo.processInfo.arguments.contains(freshInstallArgument)
    }

    static var wantsForcedSignedOut: Bool {
        isUITesting && (
            ProcessInfo.processInfo.arguments.contains(signedOutArgument)
                || !ProcessInfo.processInfo.arguments.contains(demoLoginArgument)
        )
    }

    static var wantsDemoLogin: Bool {
        ProcessInfo.processInfo.arguments.contains(demoLoginArgument)
    }

    /// Call as early as possible in `App.init` / `didFinishLaunching`.
    static func applyLaunchDefaults() {
        guard isUITesting else { return }
        UIView.setAnimationsEnabled(false)

        let defaults = UserDefaults.standard
        if wantsFreshInstall {
            defaults.set(false, forKey: "hasSeenOnboarding")
            defaults.set(false, forKey: "hasSeenTrustIntro")
            defaults.set(false, forKey: "hasCompletedNotificationPrompt")
            defaults.set(false, forKey: "hasCompletedCalendarPrompt")
            defaults.set(false, forKey: "hasCompletedSiriPrompt")
            defaults.set(false, forKey: "hasSeenFirstSendTip")
            defaults.set(false, forKey: "hasEnteredMainAppOnce")
            defaults.set(0, forKey: "mainAppOpenCount")
        } else {
            // Stable welcome / main-app surface — skip deferred permission gates.
            defaults.set(true, forKey: "hasSeenOnboarding")
            defaults.set(true, forKey: "hasSeenTrustIntro")
            defaults.set(true, forKey: "hasCompletedNotificationPrompt")
            defaults.set(true, forKey: "hasCompletedCalendarPrompt")
            defaults.set(true, forKey: "hasCompletedSiriPrompt")
            defaults.set(true, forKey: "hasSeenFirstSendTip")
            defaults.set(true, forKey: "hasEnteredMainAppOnce")
            if defaults.integer(forKey: "mainAppOpenCount") < 3 {
                defaults.set(3, forKey: "mainAppOpenCount")
            }
        }
    }
}
