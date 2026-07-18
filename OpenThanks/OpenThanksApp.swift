import SwiftUI
import UIKit

@main
struct OpenThanksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthService()
    @State private var deepLinks = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { appDelegate.auth = auth }
                .environment(auth)
                .environment(deepLinks)
                .syncAppAppearance()
                .tint(Theme.coral)
                .onOpenURL { url in
                    if url.scheme?.lowercased() == "openthanks" {
                        auth.handleDeepLink(url)
                    } else {
                        _ = deepLinks.handle(url)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var auth: AuthService?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in auth?.devicePushToken = token }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("Couldn't register for remote notifications: \(error.localizedDescription)")
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                HeartMark(size: 64)
            case .signedOut:
                if hasSeenOnboarding {
                    WelcomeView()
                } else {
                    OnboardingView { hasSeenOnboarding = true }
                }
            case .signedIn:
                if !auth.hasResolvedProfile {
                    HeartMark(size: 64)
                } else if auth.currentProfile?.isCompleteForApp == true {
                    MainTabView()
                } else {
                    EditProfileSheet(required: true)
                }
            }
        }
        // Attach inside RootView so AuthService is already in the environment.
        .deepLinkHost(deepLinks, auth: auth)
        .animation(.easeInOut(duration: 0.25), value: isSignedIn)
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
