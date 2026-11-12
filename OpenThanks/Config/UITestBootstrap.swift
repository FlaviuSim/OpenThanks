import Foundation
import UIKit

/// Launch-argument hooks for XCUITest. Keeps signed-out / signed-in flows deterministic
/// without shipping a separate test build.
enum UITestBootstrap {
    static let uiTestingArgument = "-ui-testing"
    static let freshInstallArgument = "-ui-testing-fresh"
    static let signedOutArgument = "-ui-testing-signed-out"
    static let demoLoginArgument = "-ui-testing-demo-login"
    /// With `-ui-testing`, returns a long local people list instead of the network search.
    static let searchOverflowArgument = "-ui-testing-search-overflow"

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

    /// Deterministic overflow list for Home people search. Production search is unchanged.
    static var wantsSearchOverflowFixture: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains(searchOverflowArgument)
    }

    static let searchOverflowCount = 24

    static func searchOverflowProfiles() -> [Profile] {
        (1...searchOverflowCount).map { index in
            let number = String(format: "%02d", index)
            return Profile(
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!,
                fullName: "Overflow Person \(number)",
                headline: nil,
                avatarUrl: nil,
                email: nil,
                username: "overflow\(number)",
                phone: nil,
                favoriteNonprofitEin: nil,
                favoriteNonprofitName: nil,
                favoriteNonprofitWebsite: nil,
                favoriteNonprofitHeadline: nil
            )
        }
    }

    /// Call as early as possible in `App.init` / `didFinishLaunching`.
    static func applyLaunchDefaults() {
        guard isUITesting else { return }
        // The overflow search check needs normal keyboard and scroll animation.
        UIView.setAnimationsEnabled(!wantsSearchOverflowFixture)

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
