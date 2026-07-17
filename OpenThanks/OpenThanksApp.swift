import SwiftUI
import UIKit

@main
struct OpenThanksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthService()
    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear { appDelegate.auth = auth }
                .environment(auth)
                .syncAppAppearance()
                .tint(Theme.coral)
                .onOpenURL { auth.handleDeepLink($0) }
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
                if auth.currentProfile?.isCompleteForApp == true {
                    MainTabView()
                } else {
                    EditProfileSheet(required: true)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isSignedIn)
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
