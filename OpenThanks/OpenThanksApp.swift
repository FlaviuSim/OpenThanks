import SwiftUI
import UIKit
import UserNotifications

@main
struct OpenThanksApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var auth = AuthService()
    @State private var deepLinks = DeepLinkRouter()
    @State private var userBlocks = UserBlockService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .onAppear {
                    appDelegate.auth = auth
                    appDelegate.deepLinks = deepLinks
                    WatchConnectivityService.shared.activate(auth: auth)
                    Task { @MainActor in
                        await StreakLiveActivityController.authDidBecomeReady(userId: auth.userId)
                        await userBlocks.refresh(for: auth.userId)
                    }
                }
                .onChange(of: auth.userId) { _, userId in
                    WatchConnectivityService.shared.pushAuthContext()
                    Task { @MainActor in
                        await StreakLiveActivityController.authDidBecomeReady(userId: userId)
                        await userBlocks.refresh(for: userId)
                    }
                }
                .onChange(of: auth.currentProfile?.displayName) { _, _ in
                    WatchConnectivityService.shared.pushAuthContext()
                }
                .environment(auth)
                .environment(deepLinks)
                .environment(userBlocks)
                .syncAppAppearance()
                .tint(Theme.primary)
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
                case .compose(let campaign):
                    let fromControl = ControlCenterHandoff.consumeCompose()
                    if ComposeShareHandoff.applyPendingShare() {
                        break
                    }
                    if let campaign, !fromControl {
                        Task { @MainActor in
                            await CampaignService.shared.openCompose(
                                link: campaign,
                                analyticsSource: "campaign_deeplink"
                            )
                        }
                    } else {
                        ComposeLaunchBridge.shared.queue(
                            analyticsSource: fromControl ? "control_center" : "deep_link_compose"
                        )
                    }
                case .received:
                    TabLaunchBridge.shared.queue(.received)
                case .gratitude(let id):
                    deepLinks.destination = .gratitude(id: id)
                case .home:
                    TabLaunchBridge.shared.queue(.home)
                case .notifications:
                    TabLaunchBridge.shared.queue(.notifications)
                }
            } else if let https = WidgetDeepLink.httpsMirror(of: url) {
                // Website “Open in the iOS app” buttons use openthanks://claim/…
                // Mirror to HTTPS so claim / for / profile routing stays shared.
                if DeepLinkRouter.shouldOpenOwnInspiredTab(
                    https,
                    username: auth.currentProfile?.username,
                    userId: auth.userId
                ) {
                    TabLaunchBridge.shared.queue(.profileInspired)
                } else {
                    _ = deepLinks.handle(https)
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
        WatchComposeNotification.registerCategories()
        CalendarGratitudeBackgroundRefresh.register()
        CalendarGratitudeBackgroundRefresh.schedule()
        Analytics.setup()
        RemoteImageCache.prepare()
        // Warm the campaign cache without delaying launch. Compose never waits on this.
        Task { await CampaignService.shared.refresh() }
        // Activate ASAP so Watch file transfers aren't missed before RootView appears.
        WatchConnectivityService.shared.activate(auth: nil)
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if let auth {
            WatchConnectivityService.shared.activate(auth: auth)
            WatchConnectivityService.shared.pushAuthContext()
        }
        Task { @MainActor in
            // Control Center may launch us without delivering openthanks://compose.
            if ControlCenterHandoff.consumeCompose() {
                ComposeLaunchBridge.shared.queue(analyticsSource: "control_center")
            }
            // Any foreground — schedule-first start, then full streak sync.
            await StreakLiveActivityController.handleAppBecameActive(userId: auth?.userId)
            // Re-check push/calendar person props (users flip these in iOS Settings).
            await Analytics.syncPermissionPersonProperties()
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in auth?.devicePushToken = token }
        Analytics.pushTokenRegistered()
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
        let info = notification.request.content.userInfo
        if (info[NotificationService.thankReminderTypeKey] as? String)
            == NotificationService.calendarNudgeTypeValue {
            NotificationService.recordDeliveredCalendarNudge(userInfo: info)
        }
        // Remote receive/accept while foregrounded — refresh pending cards + badge.
        if let type = info[NotificationService.thankReminderTypeKey] as? String,
           type == "gratitude_pending" || type == "gratitude_received" || type == "heart_received" {
            await MainActor.run {
                NotificationCenter.default.post(name: .pendingThanksShouldRefresh, object: nil)
            }
        }
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
            if let campaign = NotificationService.campaignContext(from: info) {
                await MainActor.run {
                    ComposeLaunchBridge.shared.queue(
                        campaignHint: campaign.prompt,
                        campaignId: campaign.id,
                        campaignDay: campaign.day,
                        analyticsSource: "notification_campaign"
                    )
                }
                break
            }
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
        case WatchVoiceDraftStore.notificationTypeValue:
            await WatchVoiceDraftStore.restorePendingComposeIfNeeded()
            await MainActor.run {
                NotificationCenter.default.post(name: .composeLaunchQueued, object: nil)
            }
        case UnsentDraftReminderStore.notificationTypeValue:
            let gratitudeId = (info[UnsentDraftReminderStore.gratitudeIdKey] as? String)
                .flatMap(UUID.init)
            if let gratitudeId {
                await UnsentDraftReminderStore.openDeliver(gratitudeId: gratitudeId)
                await MainActor.run {
                    NotificationCenter.default.post(name: .composeLaunchQueued, object: nil)
                }
            }
        case ComposeDraftStore.typeValue:
            let hasRecipient = !(ComposeDraftStore.restore()?.recipient
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            Analytics.captureDraftEvent("draft_reminder_opened", hasRecipient: hasRecipient)
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(analyticsSource: "draft_reminder")
            }
        case NotificationService.postAcceptRemindTypeValue:
            let message = info[NotificationService.postAcceptRemindMessageKey] as? String
            let parentId = (info[NotificationService.postAcceptRemindParentIdKey] as? String)
                .flatMap(UUID.init)
            let parentName = (info[NotificationService.postAcceptRemindParentNameKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                ComposeLaunchBridge.shared.queue(
                    message: message,
                    inspiredByGratitudeId: parentId,
                    inspiredByAuthorName: (parentName?.isEmpty == false) ? parentName : nil,
                    analyticsSource: "post_accept_remind"
                )
            }
        case NotificationService.calendarNudgeTypeValue:
            NotificationService.recordDeliveredCalendarNudge(userInfo: info)
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
            // Keep the row in Notifications; mark today’s saved suggestion read.
            let today = Calendar.current.startOfDay(for: Date())
            if let match = CalendarThankSuggestionStore.all().first(where: {
                Calendar.current.isDate($0.dayStart, inSameDayAs: today)
            }) {
                CalendarThankSuggestionStore.markRead(id: match.id)
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
        case "gratitude_pending":
            // Open My Feed pending section (forces Personal + scroll).
            await MainActor.run {
                NotificationCenter.default.post(name: .pendingThanksShouldRefresh, object: nil)
                TabLaunchBridge.shared.queue(.received)
            }
        case "gratitude_received", "heart_received", "heart", "reaction":
            let gratitudeId = (info["gratitude_id"] as? String).flatMap(UUID.init)
            await MainActor.run {
                if let gratitudeId {
                    deepLinks?.destination = .gratitude(id: gratitudeId)
                } else {
                    TabLaunchBridge.shared.queue(.notifications)
                }
            }
        case "email_bounced":
            let gratitudeId = (info["gratitude_id"] as? String).flatMap(UUID.init)
            await MainActor.run {
                deepLinks?.destination = .pendingSent(resendId: gratitudeId)
            }
        case "competition_winner":
            await MainActor.run {
                TabLaunchBridge.shared.queue(.notifications)
            }
        default:
            break
        }
    }
}

struct RootView: View {
    enum HomeGate {
        case checking, needsCalendar, ready
    }

    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    /// Completed when OS already decided, or after deferred post-appreciation / post-calendar ask.
    @AppStorage("hasCompletedNotificationPrompt") private var hasCompletedNotificationPrompt = false
    /// Completed after deferred 3rd-open gate (connect or skip), or when already connected.
    @AppStorage("hasCompletedCalendarPrompt") private var hasCompletedCalendarPrompt = false
    /// Legacy flag — trust beat now lives on the one-page pre-login onboarding.
    @AppStorage("hasSeenTrustIntro") private var hasSeenTrustIntro = false
    /// Legacy — “Say thanks your way” tip removed from install; keep flag true so old installs stay quiet.
    @AppStorage("hasCompletedSiriPrompt") private var hasCompletedSiriPrompt = false
    /// True after the first session that reached the main app.
    @AppStorage("hasEnteredMainAppOnce") private var hasEnteredMainAppOnce = false
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    @State private var homeGate: HomeGate = .checking
    /// One open-count increment per process when reaching `.ready`.
    @State private var countedMainAppOpenThisProcess = false
    /// Skippable first-run promise over guest browse (not shown for claim deep links).
    @State private var showSignedOutFirstRunIntro = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch auth.state {
            case .loading:
                HeartMark(size: 64)
                    .transition(.opacity)
            case .signedOut:
                // Guest Home immediately. Sign-in is a sheet at send / heart /
                // accept — never a hard wall. First-run promise is skippable and
                // is suppressed when a claim/deep link is already waiting.
                GuestBrowseShell()
                    .fullScreenCover(isPresented: $showSignedOutFirstRunIntro) {
                        OnboardingView {
                            hasSeenOnboarding = true
                            hasSeenTrustIntro = true
                            showSignedOutFirstRunIntro = false
                        }
                        .interactiveDismissDisabled(false)
                    }
                    .onAppear { reconcileSignedOutFirstRun() }
                    .onChange(of: deepLinks.destination?.id) { _, _ in
                        reconcileSignedOutFirstRun()
                    }
                    .transition(.opacity)
            case .signedIn:
                if !auth.hasResolvedProfile {
                    HeartMark(size: 64)
                        .transition(.opacity)
                } else {
                    // Straight into the app. Calendar waits until after the first thank-you.
                    // Notifications wait until send/receive (or after calendar connect).
                    // Start the store lookup early so Home can show an update immediately.
                    signedInHome
                        .onAppear { AppUpdateChecker.shared.checkIfNeeded() }
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
        case .needsCalendar:
            CalendarPermissionView(
                onFinished: {
                    hasCompletedCalendarPrompt = true
                    homeGate = gateAfterCalendarOrReady()
                },
                analyticsSource: "deferred_open",
                marksLaunchGateCompleteOnSkip: true,
                countsTowardAutomaticCap: true
            )
        case .ready:
            MainTabView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func gateAfterCalendarOrReady() -> HomeGate {
        // Pre-login onboarding now carries the trust beat.
        if !hasSeenTrustIntro { hasSeenTrustIntro = true }
        if !hasCompletedSiriPrompt { hasCompletedSiriPrompt = true }
        return .ready
    }

    private var effectiveHomeGate: HomeGate {
        if homeGate == .needsCalendar {
            return .needsCalendar
        }
        if homeGate == .checking {
            return .checking
        }
        return .ready
    }

    /// Re-check only when the signed-in user / profile resolution changes.
    /// Do **not** include AppStorage flags or open-count here — `resolveHomeGate`
    /// mutates those, which would cancel this `.task` mid-flight and leave the
    /// heart splash stuck on `.checking` (common after logout → Sign in with Apple).
    /// Claim / profile / gratitude links skip the intro so accept isn’t buried.
    private func reconcileSignedOutFirstRun() {
        if deepLinks.destination != nil {
            if !hasSeenOnboarding {
                hasSeenOnboarding = true
                hasSeenTrustIntro = true
            }
            showSignedOutFirstRunIntro = false
            return
        }
        showSignedOutFirstRunIntro = !hasSeenOnboarding
    }

    private var homeGateTaskID: String {
        let user = auth.userId?.uuidString ?? "out"
        return "\(user)-\(auth.hasResolvedProfile)"
    }

    private func resolveHomeGate() async {
        guard case .signedIn = auth.state, auth.hasResolvedProfile else {
            homeGate = .checking
            return
        }

        do {
            try await resolveHomeGateBody()
        } catch is CancellationError {
            // Replacement task (new sign-in) owns the outcome — don't clear `.ready`.
            return
        } catch {
            // Never leave the splash forever on a transient permission/network glitch.
            if case .signedIn = auth.state, auth.hasResolvedProfile, homeGate == .checking {
                homeGate = .ready
            }
        }
    }

    private func resolveHomeGateBody() async throws {
        try Task.checkCancellation()

        OpenThanksShortcuts.updateAppShortcutParameters()

        // Count this process as a main-app open. Calendar waits until a thank-you exists.
        let openCount = PermissionPromptScheduler.recordMainAppOpenIfNeeded(
            processAlreadyCounted: &countedMainAppOpenThisProcess
        )
        if openCount >= 1 {
            hasEnteredMainAppOnce = true
        }

        // Returning users who never saw the new one-pager still skip TrustIntro.
        if !hasSeenTrustIntro { hasSeenTrustIntro = true }
        // “Say thanks your way” tip removed — mark complete so it never gates Home.
        if !hasCompletedSiriPrompt { hasCompletedSiriPrompt = true }

        try Task.checkCancellation()

        // Notifications are deferred until send/receive — only sync if OS already decided.
        if !hasCompletedNotificationPrompt {
            if await NotificationService.hasResolvedAuthorization() {
                try Task.checkCancellation()
                if await NotificationService.isAuthorized() {
                    let failure = await NotificationService.enableFridayReminder(
                        analyticsSource: "deferred_sync"
                    )
                    fridayReminderEnabled = failure == nil
                }
                hasCompletedNotificationPrompt = true
            }
            // else: leave incomplete so post-appreciation can offer the branded ask.
        }

        try Task.checkCancellation()

        // Opens before the first send do not show the automatic calendar prompt.
        // Remember that so those opens don't spend the two-show cap later.
        CalendarPromptCap.notePreSendOpensIgnoredIfNeeded(
            hasSentFirstThankYou: FirstThanksSent.hasSent(),
            in: .standard
        )

        if !hasCompletedCalendarPrompt {
            if CalendarMeetingAggregator.hasAnyConnectedSource {
                // Already connected — silently mark done; keep nudge on when possible.
                // Do not await nudge refresh here — that path hits server / EventKit / on-device
                // AI and left returning users stuck on the heart splash after App Store updates.
                hasCompletedCalendarPrompt = true
                calendarNudgeEnabled = true
            } else if PermissionPromptScheduler.shouldShowDeferredCalendarGate {
                // Later open, after the first thank-you — full-screen calendar connect.
                homeGate = .needsCalendar
                return
            }
            // No thank-you yet, or still inside the cap's quiet period.
        }

        try Task.checkCancellation()
        // Open Home first. Friday + calendar nudges are best-effort and must not
        // gate the heart splash (URLSession / EventKit can hang for a long time).
        homeGate = gateAfterCalendarOrReady()

        let refreshFriday = fridayReminderEnabled && hasCompletedNotificationPrompt
        let refreshCalendar = calendarNudgeEnabled && hasCompletedCalendarPrompt
        guard refreshFriday || refreshCalendar else { return }

        let authorId = auth.userId
        var emails = Set<String>()
        if let email = auth.currentProfile?.email?.lowercased() {
            emails.insert(email)
        }
        Task {
            if refreshFriday {
                await NotificationService.refreshFridayReminderIfEnabled(true)
            }
            if refreshCalendar {
                await NotificationService.refreshCalendarGratitudeNudgeIfEnabled(
                    true,
                    authorId: authorId,
                    selfEmails: emails
                )
                CalendarGratitudeBackgroundRefresh.schedule()
            }
        }
    }

    private var isSignedIn: Bool {
        if case .signedIn = auth.state { return true }
        return false
    }
}
