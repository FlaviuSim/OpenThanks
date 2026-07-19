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
    enum NotificationGate {
        case checking, needsPrompt, ready
    }

    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// One-time gate after profile is ready — ask for Friday reminder notifications.
    @AppStorage("hasCompletedNotificationPrompt") private var hasCompletedNotificationPrompt = false
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @State private var notificationGate: NotificationGate = .checking

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                HeartMark(size: 64)
                    .transition(.opacity)
            case .signedOut:
                Group {
                    if hasSeenOnboarding {
                        WelcomeView()
                    } else {
                        OnboardingView { hasSeenOnboarding = true }
                    }
                }
                .transition(.opacity)
            case .signedIn:
                if !auth.hasResolvedProfile && auth.currentProfile?.isCompleteForApp != true {
                    HeartMark(size: 64)
                        .transition(.opacity)
                } else if auth.currentProfile?.isCompleteForApp != true {
                    EditProfileSheet(required: true)
                        .transition(.opacity)
                } else {
                    signedInHome
                        .transition(.opacity)
                }
            }
        }
        // Attach inside RootView so AuthService is already in the environment.
        .deepLinkHost(deepLinks, auth: auth)
        .animation(.easeInOut(duration: 0.28), value: isSignedIn)
        .animation(.easeInOut(duration: 0.28), value: auth.hasResolvedProfile)
        .animation(.easeInOut(duration: 0.22), value: notificationGate)
        .task(id: notificationTaskID) {
            await resolveNotificationGate()
        }
    }

    @ViewBuilder
    private var signedInHome: some View {
        // Avoid a HeartMark flash when the prompt was already completed.
        let gate = effectiveNotificationGate
        switch gate {
        case .checking:
            HeartMark(size: 64)
        case .needsPrompt:
            NotificationPermissionView {
                hasCompletedNotificationPrompt = true
                notificationGate = .ready
            }
        case .ready:
            MainTabView()
        }
    }

    private var effectiveNotificationGate: NotificationGate {
        if hasCompletedNotificationPrompt { return .ready }
        return notificationGate
    }

    /// Re-check when the user finishes profile (or signs in) before entering the app.
    private var notificationTaskID: String {
        let user = auth.userId?.uuidString ?? "out"
        let ready = auth.hasResolvedProfile && auth.currentProfile?.isCompleteForApp == true
        return "\(user)-\(ready)-\(hasCompletedNotificationPrompt)"
    }

    private func resolveNotificationGate() async {
        guard case .signedIn = auth.state,
              auth.hasResolvedProfile,
              auth.currentProfile?.isCompleteForApp == true
        else {
            notificationGate = .checking
            return
        }

        if hasCompletedNotificationPrompt {
            notificationGate = .ready
            return
        }

        // Already decided at the system level — never show our ask screen.
        if await NotificationService.hasResolvedAuthorization() {
            if await NotificationService.isAuthorized() {
                let enabled = await NotificationService.enableFridayReminder()
                fridayReminderEnabled = enabled
            }
            hasCompletedNotificationPrompt = true
            notificationGate = .ready
            return
        }

        notificationGate = .needsPrompt
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
