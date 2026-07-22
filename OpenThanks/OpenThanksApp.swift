import SwiftUI
import UIKit
import UserNotifications

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
                        if WidgetDeepLink.isAuthCallback(url) {
                            auth.handleDeepLink(url)
                        } else if let destination = WidgetDeepLink.parse(url) {
                            switch destination {
                            case .compose:
                                ComposeShareHandoff.queuePendingShareOrBlank()
                            case .received:
                                TabLaunchBridge.shared.queue(.received)
                            case .home:
                                TabLaunchBridge.shared.queue(.home)
                            }
                        } else {
                            // Unknown custom-scheme URLs — try auth (Supabase variants).
                            auth.handleDeepLink(url)
                        }
                    } else {
                        _ = deepLinks.handle(url)
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var auth: AuthService?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let type = info[NotificationService.thankReminderTypeKey] as? String else { return }

        await MainActor.run {
            switch type {
            case NotificationService.thankReminderTypeValue:
                let name = info[NotificationService.thankReminderNameKey] as? String
                ComposeLaunchBridge.shared.queue(recipientName: name)
            case NotificationService.fridayReminderTypeValue:
                ComposeLaunchBridge.shared.queue()
            default:
                break
            }
        }
    }
}

struct RootView: View {
    enum HomeGate {
        case checking, needsNotifications, needsSiriTip, ready
    }

    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// One-time gate after profile is ready — ask for Friday reminder notifications.
    @AppStorage("hasCompletedNotificationPrompt") private var hasCompletedNotificationPrompt = false
    /// One-time tip so people discover App Shortcuts / Siri phrases.
    @AppStorage("hasCompletedSiriPrompt") private var hasCompletedSiriPrompt = false
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @State private var homeGate: HomeGate = .checking

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
        .animation(.easeInOut(duration: 0.22), value: homeGate)
        .task(id: homeGateTaskID) {
            await resolveHomeGate()
        }
    }

    @ViewBuilder
    private var signedInHome: some View {
        switch effectiveHomeGate {
        case .checking:
            HeartMark(size: 64)
        case .needsNotifications:
            NotificationPermissionView {
                hasCompletedNotificationPrompt = true
                homeGate = hasCompletedSiriPrompt ? .ready : .needsSiriTip
            }
        case .needsSiriTip:
            SiriIntroView {
                hasCompletedSiriPrompt = true
                homeGate = .ready
            }
        case .ready:
            MainTabView()
        }
    }

    private var effectiveHomeGate: HomeGate {
        if !hasCompletedNotificationPrompt {
            return homeGate == .needsNotifications ? .needsNotifications : homeGate
        }
        if !hasCompletedSiriPrompt {
            return .needsSiriTip
        }
        return .ready
    }

    /// Re-check when the user finishes profile (or signs in) before entering the app.
    private var homeGateTaskID: String {
        let user = auth.userId?.uuidString ?? "out"
        let ready = auth.hasResolvedProfile && auth.currentProfile?.isCompleteForApp == true
        return "\(user)-\(ready)-\(hasCompletedNotificationPrompt)-\(hasCompletedSiriPrompt)"
    }

    private func resolveHomeGate() async {
        guard case .signedIn = auth.state,
              auth.hasResolvedProfile,
              auth.currentProfile?.isCompleteForApp == true
        else {
            homeGate = .checking
            return
        }

        OpenThanksShortcuts.updateAppShortcutParameters()

        if !hasCompletedNotificationPrompt {
            if await NotificationService.hasResolvedAuthorization() {
                if await NotificationService.isAuthorized() {
                    let enabled = await NotificationService.enableFridayReminder()
                    fridayReminderEnabled = enabled
                }
                hasCompletedNotificationPrompt = true
            } else {
                homeGate = .needsNotifications
                return
            }
        }

        if fridayReminderEnabled, hasCompletedNotificationPrompt {
            await NotificationService.refreshFridayReminderIfEnabled(true)
        }

        if !hasCompletedSiriPrompt {
            homeGate = .needsSiriTip
            return
        }

        homeGate = .ready
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
