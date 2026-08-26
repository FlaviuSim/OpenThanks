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
                .onAppear {
                    appDelegate.auth = auth
                    appDelegate.deepLinks = deepLinks
                    WatchConnectivityService.shared.activate(auth: auth)
                    Task { @MainActor in
                        await StreakLiveActivityController.authDidBecomeReady(userId: auth.userId)
                    }
                }
                .onChange(of: auth.userId) { _, userId in
                    WatchConnectivityService.shared.pushAuthContext()
                    Task { @MainActor in
                        await StreakLiveActivityController.authDidBecomeReady(userId: userId)
                    }
                }
                .onChange(of: auth.currentProfile?.displayName) { _, _ in
                    WatchConnectivityService.shared.pushAuthContext()
                }
                .environment(auth)
                .environment(deepLinks)
                .syncAppAppearance()
                .tint(Theme.coral)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme?.lowercased() == "openthanks" {
            if WidgetDeepLink.isAuthCallback(url) {
                auth.handleDeepLink(url)
            } else if let destination = WidgetDeepLink.parse(url) {
                switch destination {
                case .compose:
                    ComposeShareHandoff.queuePendingShareOrBlank()
                case .received:
                    TabLaunchBridge.shared.queue(.received)
                case .gratitude(let id):
                    deepLinks.destination = .gratitude(id: id)
                case .home:
                    TabLaunchBridge.shared.queue(.home)
                case .notifications:
                    TabLaunchBridge.shared.queue(.notifications)
                }
            } else {
                // Unknown custom-scheme URLs — try auth (Supabase variants).
                auth.handleDeepLink(url)
            }
        } else {
            if DeepLinkRouter.shouldOpenOwnInspiredTab(
                url,
                username: auth.currentProfile?.username,
                userId: auth.userId
            ) {
                TabLaunchBridge.shared.queue(.profileInspired)
                return
            }
            _ = deepLinks.handle(url)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var auth: AuthService?
    weak var deepLinks: DeepLinkRouter?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        CalendarGratitudeBackgroundRefresh.register()
        CalendarGratitudeBackgroundRefresh.schedule()
        Analytics.setup()
        RemoteImageCache.prepare()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if let auth {
            WatchConnectivityService.shared.activate(auth: auth)
            WatchConnectivityService.shared.pushAuthContext()
        }
        Task { @MainActor in
            // Any foreground — schedule-first start, then full streak sync.
            await StreakLiveActivityController.handleAppBecameActive(userId: auth?.userId)
        }
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
        // Any banner delivery while the app is open — not only the 8am streak wake.
        await StreakLiveActivityController.handleAppBecameActive(userId: auth?.userId)
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Cold-start / tap from any local or remote notification — start grace-day
        // Live Activity before routing to compose, feed, etc.
        await StreakLiveActivityController.handleAppBecameActive(userId: auth?.userId)

        let info = response.notification.request.content.userInfo
        guard let type = info[NotificationService.thankReminderTypeKey] as? String else { return }

        switch type {
        case NotificationService.thankReminderTypeValue:
            let name = info[NotificationService.thankReminderNameKey] as? String
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(recipientName: name, analyticsSource: "notification_thank_reminder")
            }
        case NotificationService.fridayReminderTypeValue:
            let promptDate: Date = {
                if let interval = info[NotificationService.fridayPromptDateKey] as? TimeInterval {
                    return Date(timeIntervalSince1970: interval)
                }
                return Date()
            }()
            let starter = FridayPrompts.prompt(for: promptDate).starterIdea
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(
                    messagePlaceholder: starter,
                    analyticsSource: "notification_friday"
                )
            }
        case NotificationService.calendarNudgeTypeValue:
            let name = (info[NotificationService.calendarNudgeNameKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = info[NotificationService.calendarNudgeMessageKey] as? String
            let email = (info[NotificationService.calendarNudgeEmailKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Prefer calendar email in To — no OpenThanks profile lookup.
            let toField: String?
            if let email, !email.isEmpty {
                toField = email
            } else if let name, !name.isEmpty {
                toField = name
            } else {
                toField = nil
            }
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(
                    recipientName: toField,
                    message: message,
                    analyticsSource: "calendar_evening_nudge"
                )
            }
        case NotificationService.streakLiveActivityWakeTypeValue:
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(analyticsSource: "streak_live_activity_wake")
            }
        case "email_bounced":
            let gratitudeId = (info["gratitude_id"] as? String).flatMap(UUID.init)
            await MainActor.run {
                deepLinks?.destination = .pendingSent(resendId: gratitudeId)
            }
        default:
            break
        }
    }
}

struct RootView: View {
    enum HomeGate {
        case checking, needsNotifications, needsCalendar, needsProfile, needsSiriTip, ready
    }

    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// One-time gate after sign-in — ask for Friday reminder notifications.
    @AppStorage("hasCompletedNotificationPrompt") private var hasCompletedNotificationPrompt = false
    /// One-time gate for calendar access (evening thank-you nudges).
    @AppStorage("hasCompletedCalendarPrompt") private var hasCompletedCalendarPrompt = false
    /// One-time tip so people discover App Shortcuts / Siri phrases.
    @AppStorage("hasCompletedSiriPrompt") private var hasCompletedSiriPrompt = false
    /// True after the first session that reached the main app — Siri tip waits until the next launch.
    @AppStorage("hasEnteredMainAppOnce") private var hasEnteredMainAppOnce = false
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var homeGate: HomeGate = .checking
    /// Keeps the deferred Siri tip from appearing again during the same process.
    @State private var deferredSiriThisProcess = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                HeartMark(size: 64)
                    .transition(.opacity)
            case .signedOut:
                // Description slides → sign-in only. Never ask for notifications/calendar here.
                Group {
                    if hasSeenOnboarding {
                        WelcomeView()
                    } else {
                        OnboardingView { hasSeenOnboarding = true }
                    }
                }
                .transition(.opacity)
            case .signedIn:
                if !auth.hasResolvedProfile {
                    HeartMark(size: 64)
                        .transition(.opacity)
                } else {
                    // After login: notifications → calendar → profile → app
                    // (Siri tip on the second open).
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
                homeGate = nextGateAfterNotifications()
            }
        case .needsCalendar:
            CalendarPermissionView {
                hasCompletedCalendarPrompt = true
                homeGate = nextGateAfterCalendar()
            }
        case .needsProfile:
            EditProfileSheet(required: true)
        case .needsSiriTip:
            SiriIntroView {
                hasCompletedSiriPrompt = true
                homeGate = .ready
            }
        case .ready:
            MainTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func nextGateAfterNotifications() -> HomeGate {
        if !hasCompletedCalendarPrompt { return .needsCalendar }
        return nextGateAfterCalendar()
    }

    private func nextGateAfterCalendar() -> HomeGate {
        if auth.currentProfile?.isCompleteForApp != true { return .needsProfile }
        return gateAfterProfileComplete()
    }

    /// Siri tip waits until the second app open to avoid first-session overload.
    private var shouldShowSiriTipNow: Bool {
        !hasCompletedSiriPrompt && hasEnteredMainAppOnce && !deferredSiriThisProcess
    }

    private func gateAfterProfileComplete() -> HomeGate {
        if shouldShowSiriTipNow { return .needsSiriTip }
        if !hasCompletedSiriPrompt, !hasEnteredMainAppOnce {
            hasEnteredMainAppOnce = true
            deferredSiriThisProcess = true
        }
        return .ready
    }

    private var effectiveHomeGate: HomeGate {
        if !hasCompletedNotificationPrompt {
            return homeGate == .needsNotifications ? .needsNotifications : homeGate
        }
        if !hasCompletedCalendarPrompt {
            return homeGate == .needsCalendar ? .needsCalendar : homeGate
        }
        if auth.currentProfile?.isCompleteForApp != true {
            return .needsProfile
        }
        if homeGate == .checking {
            return .checking
        }
        if shouldShowSiriTipNow {
            return .needsSiriTip
        }
        return .ready
    }

    /// Re-check when the user signs in, finishes permissions, or completes profile.
    private var homeGateTaskID: String {
        let user = auth.userId?.uuidString ?? "out"
        let resolved = auth.hasResolvedProfile
        let complete = auth.currentProfile?.isCompleteForApp == true
        return "\(user)-\(resolved)-\(complete)-\(hasCompletedNotificationPrompt)-\(hasCompletedCalendarPrompt)-\(hasCompletedSiriPrompt)-\(hasEnteredMainAppOnce)"
    }

    private func resolveHomeGate() async {
        guard case .signedIn = auth.state, auth.hasResolvedProfile else {
            homeGate = .checking
            return
        }

        OpenThanksShortcuts.updateAppShortcutParameters()

        if !hasCompletedNotificationPrompt {
            if await NotificationService.hasResolvedAuthorization() {
                if await NotificationService.isAuthorized() {
                    let failure = await NotificationService.enableFridayReminder()
                    fridayReminderEnabled = failure == nil
                }
                hasCompletedNotificationPrompt = true
            } else {
                homeGate = .needsNotifications
                return
            }
        }

        if !hasCompletedCalendarPrompt {
            if CalendarMeetingAggregator.hasAnyConnectedSource {
                // Already connected (Apple and/or Google) — keep nudge on and schedule.
                calendarNudgeEnabled = true
                var emails = Set<String>()
                if let email = auth.currentProfile?.email?.lowercased() {
                    emails.insert(email)
                }
                await NotificationService.refreshCalendarGratitudeNudgeIfEnabled(
                    true,
                    authorId: auth.userId,
                    selfEmails: emails
                )
                CalendarGratitudeBackgroundRefresh.schedule()
                hasCompletedCalendarPrompt = true
            } else {
                homeGate = .needsCalendar
                return
            }
        }

        if auth.currentProfile?.isCompleteForApp != true {
            homeGate = .needsProfile
            return
        }

        if fridayReminderEnabled, hasCompletedNotificationPrompt {
            await NotificationService.refreshFridayReminderIfEnabled(true)
        }

        if calendarNudgeEnabled, hasCompletedCalendarPrompt {
            var emails = Set<String>()
            if let email = auth.currentProfile?.email?.lowercased() {
                emails.insert(email)
            }
            await NotificationService.refreshCalendarGratitudeNudgeIfEnabled(
                true,
                authorId: auth.userId,
                selfEmails: emails
            )
            CalendarGratitudeBackgroundRefresh.schedule()
        }

        homeGate = gateAfterProfileComplete()
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
