import SwiftUI
import UIKit

struct MainTabView: View {
    enum Tab: Hashable { case feed, notifications, profile }

    private enum ComposeSheet: Identifiable {
        case launch(ComposeLaunchBridge.Request)

        var id: String {
            switch self {
            case .launch(let request): request.id.uuidString
            }
        }

        /// Empty `app_open` / `post_login` — notification and calendar launches replace these.
        /// The heart button is not weak: a fixed `"blank"` id plus the weak early-return
        /// left `composeSheet` set when the cover never appeared, and every later tap
        /// was ignored so `tab_compose` never fired.
        var isWeakDefault: Bool {
            switch self {
            case .launch(let request): request.isWeakDefault
            }
        }
    }

    /// FAB / sidebar “Thank Someone”. A new id every tap so the item cover presents again.
    private static func tabComposeSheet() -> ComposeSheet {
        .launch(ComposeLaunchBridge.Request(analyticsSource: "tab_compose"))
    }

    @State private var tab: Tab = .feed
    @State private var composeSheet: ComposeSheet?
    /// Drops overlapping presentCompose Tasks (onAppear + scenePhase both fire on launch).
    @State private var composePresentGeneration = 0
    /// Tracks whether the in-flight `presentCompose` is blank/`app_open` so a deferred
    /// cold-start default doesn't clobber a calendar / notification prefill mid-delay.
    @State private var composePresentIntentIsWeak = true
    /// True while a presentCompose sleep is still going to assign `composeSheet`.
    @State private var composePresentInFlight = false
    @State private var unreadCount = 0
    @State private var feedPath = NavigationPath()
    @State private var notificationsPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var showProfileSettings = false
    /// Home people-search is focused — hide the tab bar (native search-mode UX).
    @State private var homeSearchActive = false
    /// Feed scrolled down — tuck the floating pill / FAB (and FeedView header).
    @State private var homeChromeCollapsed = false
    /// Selected post for iPad list↔detail on Home.
    @State private var feedDetail: Gratitude?
    /// Selected notification route for iPad list↔detail.
    @State private var notificationDetail: GratitudeIdRoute?
    @Environment(AuthService.self) private var auth
    @Environment(DeepLinkRouter.self) private var deepLinks
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true
    /// One-time Home tip pointing at the heart compose button.
    @AppStorage("hasSeenFirstSendTip") private var hasSeenFirstSendTip = false
    /// Opens of the composer on this device. Does not flip `hasSeenFirstSendTip`.
    @State private var hasOpenedComposer = FirstSendTip.hasOpenedComposer()
    /// Successful creates on this device (`EnjoymentPrompt.successfulSendCountKey`).
    @AppStorage(EnjoymentPrompt.successfulSendCountKey) private var successfulSendCount = 0
    /// True while the post-accept ripple sheet is pending or visible.
    @State private var rippleSheetPresented = false
    @State private var pendingAcceptCount = 0
    @State private var didLogFirstSendTipShown = false
    /// Deferred notification / calendar sheets after send or accept.
    @State private var permissionScheduler = PermissionPromptScheduler.shared
    @State private var appVisits = AppVisitCenter.shared
    @State private var updateChecker = AppUpdateChecker.shared

    private var usesSidebar: Bool { sizeClass == .regular }

    private var showPermissionPrompt: Binding<Bool> {
        Binding(
            get: { permissionScheduler.pending != nil },
            set: { presented in
                if !presented {
                    permissionScheduler.clearPending()
                }
            }
        )
    }
    private var shouldShowFirstSendTip: Bool {
        FirstSendTip.shouldShow(
            hasSeenTip: hasSeenFirstSendTip,
            isFeedTab: tab == .feed,
            tabComposerPresented: composeSheet != nil,
            searchActive: homeSearchActive,
            pendingAcceptCount: pendingAcceptCount,
            rippleSheetPresented: rippleSheetPresented,
            hasOpenedComposer: hasOpenedComposer,
            hasSentAppreciation: successfulSendCount > 0
        ) && !homeChromeCollapsed
    }

    var body: some View {
        Group {
            if usesSidebar {
                sidebarShell
            } else {
                phoneShell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .syncAppAppearance()
        // Keep Observation tracking on `pending` so the deferred sheet presents.
        .animation(.easeInOut(duration: 0.2), value: permissionScheduler.pending != nil)
        .sheet(isPresented: $showProfileSettings) {
            SettingsView()
                .syncAppAppearance()
        }
        .sheet(isPresented: showPermissionPrompt) {
            permissionPromptSheet
        }
        .composeCover(item: $composeSheet) { sheet in
            composeView(for: sheet)
        }
        .task { await refreshUnread() }
        .onAppear { CampaignPushOffer.interfaceReady = true }
        .onAppear {
            // Pending CTAs only — do not auto-open blank compose on every launch.
            presentLaunchSurfaces()
            AppUpdateChecker.shared.checkIfNeeded()
            CalendarConnectReminder.shared.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationsShouldRefresh)) { _ in
            Task { await refreshUnread() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gratitudeAccepted)) { _ in
            Task { await refreshUnread() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .composeLaunchQueued)) { _ in
            presentPendingComposeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabLaunchQueued)) { _ in
            presentPendingTabIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { @MainActor in
                await StreakLiveActivityController.handleAppBecameActive(userId: auth.userId)
            }
            // Resume any queued compose/tab from notifications / deep links / share.
            // Do not open blank compose just because the icon was tapped.
            presentLaunchSurfaces()
            AppUpdateChecker.shared.checkIfNeeded()
            CalendarConnectReminder.shared.refresh()
            // Pending receives can land while backgrounded — refresh Home cards + badge.
            NotificationCenter.default.post(name: .pendingThanksShouldRefresh, object: nil)
            Task {
                await CampaignService.shared.refresh()
                await refreshUnread()
                if let userId = auth.userId {
                    let pending = (try? await GratitudeService.pending(authorId: userId)) ?? []
                    await UnsentDraftReminderStore.reconcile(pending: pending)
                }
                if fridayReminderEnabled {
                    await NotificationService.refreshFridayReminderIfEnabled(true)
                }
                if calendarNudgeEnabled {
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
            }
        }
        .animation(.easeInOut(duration: 0.18), value: tab)
        .onChange(of: tab) { _, newTab in
            if newTab != .feed {
                homeSearchActive = false
                homeChromeCollapsed = false
                resignKeyboard()
            }
            // Keep list↔detail selection when switching tabs so return feels continuous.
        }
        .onReceive(NotificationCenter.default.publisher(for: .homePendingAcceptCount)) { note in
            if let count = note.userInfo?["count"] as? Int {
                pendingAcceptCount = count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payItForwardSheetPresented)) { note in
            if let presented = note.userInfo?["presented"] as? Bool {
                rippleSheetPresented = presented
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: FirstSendTip.composerOpened)) { _ in
            hasOpenedComposer = true
        }
        .onChange(of: composeSheet != nil) { _, open in
            if open {
                homeSearchActive = false
                homeChromeCollapsed = false
                resignKeyboard()
                if !hasSeenFirstSendTip {
                    hasSeenFirstSendTip = true
                }
            } else {
                CalendarConnectReminder.shared.refresh()
            }
        }
        .onChange(of: shouldShowFirstSendTip) { _, show in
            if show, !didLogFirstSendTipShown {
                didLogFirstSendTipShown = true
                Analytics.capture("first_send_tip_shown")
            }
        }
    }

    @ViewBuilder
    private var permissionPromptSheet: some View {
        NavigationStack {
            Group {
                switch permissionScheduler.pending {
                case .notificationsAppreciation(let source):
                    NotificationPermissionView(
                        onFinished: {
                            let finished = PermissionPromptScheduler.Prompt.notificationsAppreciation(source: source)
                            permissionScheduler.advanceAfterFinishing(finished)
                        },
                        pitch: .appreciation,
                        analyticsSource: source
                    )
                case .notificationsAfterCalendar(let source):
                    NotificationPermissionView(
                        onFinished: {
                            let finished = PermissionPromptScheduler.Prompt.notificationsAfterCalendar(source: source)
                            permissionScheduler.advanceAfterFinishing(finished)
                            CalendarConnectReminder.shared.refresh()
                        },
                        pitch: .postCalendar,
                        analyticsSource: source
                    )
                case .notificationsCampaign(let source):
                    NotificationPermissionView(
                        onFinished: {
                            let finished = PermissionPromptScheduler.Prompt.notificationsCampaign(source: source)
                            permissionScheduler.advanceAfterFinishing(finished)
                        },
                        pitch: .campaign,
                        analyticsSource: source
                    )
                case .calendar(let source):
                    CalendarPermissionView(
                        onFinished: {
                            let finished = PermissionPromptScheduler.Prompt.calendar(source: source)
                            permissionScheduler.advanceAfterFinishing(finished)
                            CalendarConnectReminder.shared.refresh()
                        },
                        analyticsSource: source,
                        marksLaunchGateCompleteOnSkip: false,
                        countsTowardAutomaticCap: true
                    )
                case .none:
                    Color.clear
                        .onAppear { permissionScheduler.clearPending() }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        if let pending = permissionScheduler.pending {
                            // Closing a calendar sheet snoozes re-ask; notif close marks completed.
                            switch pending {
                            case .calendar:
                                PermissionPromptScheduler.shared.snoozeAppreciationCalendarPrompt()
                            case .notificationsAppreciation, .notificationsAfterCalendar:
                                PermissionPromptScheduler.shared.markNotificationPromptCompleted()
                            case .notificationsCampaign:
                                break
                            }
                            permissionScheduler.advanceAfterFinishing(pending)
                        } else {
                            permissionScheduler.clearPending()
                        }
                        CalendarConnectReminder.shared.refresh()
                    }
                    .font(Theme.body(16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .syncAppAppearance()
        .presentationDetents([.large])
    }

    // MARK: - iPad sidebar shell

    private var sidebarShell: some View {
        NavigationSplitView {
            List {
                Section {
                    sidebarRow(title: "Home", systemImage: "house.fill", value: .feed)
                    Button {
                        selectTab(.notifications)
                    } label: {
                        Label {
                            HStack {
                                Text("Notifications")
                                if unreadCount > 0 {
                                    Spacer(minLength: 8)
                                    Text("\(min(unreadCount, 99))")
                                        .font(Theme.body(12, weight: .bold))
                                        .foregroundStyle(Theme.onPrimary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Theme.primary, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(tab == .notifications ? Theme.primary : Theme.textPrimary)
                    .listRowBackground(tab == .notifications ? Theme.brandTint : Color.clear)

                    sidebarRow(title: "Profile", systemImage: "person.fill", value: .profile)
                }

                Section {
                    Button {
                        presentCompose(Self.tabComposeSheet())
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                            Text("Thank Someone")
                                .font(Theme.body(16, weight: .semibold))
                        }
                        .foregroundStyle(Theme.onPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .accessibilityLabel("Thank Someone")
                }

                Section {
                    Button {
                        resignKeyboard()
                        homeSearchActive = false
                        showProfileSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
            }
            .listStyle(.sidebar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BrandLockup()
                }
            }
        } detail: {
            VStack(spacing: 0) {
                appUpdateBanner
                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: updateChecker.shouldShowBanner)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(title: String, systemImage: String, value: Tab) -> some View {
        Button {
            selectTab(value)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == value ? Theme.primary : Theme.textPrimary)
        .listRowBackground(tab == value ? Theme.brandTint : Color.clear)
    }

    /// Keep stacks mounted (like phone) so tab switches stay instant and image cache survives.
    private var detailColumn: some View {
        ZStack {
            FeedView(
                path: $feedPath,
                isSelected: tab == .feed,
                searchActive: $homeSearchActive,
                chromeCollapsed: $homeChromeCollapsed,
                splitSelection: $feedDetail
            )
            .opacity(tab == .feed ? 1 : 0)
            .allowsHitTesting(tab == .feed)
            .zIndex(tab == .feed ? 1 : 0)

            NotificationsView(
                path: $notificationsPath,
                unreadCount: $unreadCount,
                isSelected: tab == .notifications,
                splitSelection: $notificationDetail
            )
            .opacity(tab == .notifications ? 1 : 0)
            .allowsHitTesting(tab == .notifications)
            .zIndex(tab == .notifications ? 1 : 0)

            ProfileView(path: $profilePath, showSettings: $showProfileSettings)
                .opacity(tab == .profile ? 1 : 0)
                .allowsHitTesting(tab == .profile)
                .zIndex(tab == .profile ? 1 : 0)
        }
    }

    // MARK: - iPhone shell

    private var phoneShell: some View {
        // Pin with a bottom overlay (not a ZStack sibling). After OTP / login the
        // keyboard safe-area can linger and compress a bottom stack, which leaves
        // the floating bar mid-feed. Avoid `.move(edge:)` transitions — an
        // interrupted insert (compose auto-presents ~350ms after login) can freeze
        // the bar halfway up the screen.
        VStack(spacing: 0) {
            appUpdateBanner
            phoneTabs
        }
        .animation(.easeInOut(duration: 0.2), value: updateChecker.shouldShowBanner)
    }

    /// Update notice sits above every tab, including while the first-send tip is up.
    @ViewBuilder
    private var appUpdateBanner: some View {
        if updateChecker.shouldShowBanner {
            AppUpdateBanner(
                storeVersion: updateChecker.storeVersion,
                onUpdate: { updateChecker.openAppStore() },
                onLater: { updateChecker.snooze() }
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .readableWidth()
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .transition(.opacity)
            .onAppear { updateChecker.trackBannerShown() }
        }
    }

    private var phoneTabs: some View {
        ZStack {
            FeedView(
                path: $feedPath,
                isSelected: tab == .feed,
                searchActive: $homeSearchActive,
                chromeCollapsed: $homeChromeCollapsed
            )
            .opacity(tab == .feed ? 1 : 0)
            .allowsHitTesting(tab == .feed)
            .zIndex(tab == .feed ? 1 : 0)

            NotificationsView(
                path: $notificationsPath,
                unreadCount: $unreadCount,
                isSelected: tab == .notifications
            )
            .opacity(tab == .notifications ? 1 : 0)
            .allowsHitTesting(tab == .notifications)
            .zIndex(tab == .notifications ? 1 : 0)

            ProfileView(path: $profilePath, showSettings: $showProfileSettings)
                .opacity(tab == .profile ? 1 : 0)
                .allowsHitTesting(tab == .profile)
                .zIndex(tab == .profile ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showFloatingChrome {
                floatingChrome
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowFirstSendTip {
                VStack(alignment: .trailing, spacing: 0) {
                    firstSendTipOverlay
                        .padding(.leading, 20)
                        .padding(.trailing, 16)
                    // Clearance under the tip so it sits above the FAB.
                    Color.clear
                        .frame(height: 96)
                        .allowsHitTesting(false)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(20)
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.smooth(duration: 0.28), value: homeSearchActive)
        .animation(.smooth(duration: 0.28), value: homeChromeCollapsed)
        .animation(.easeInOut(duration: 0.22), value: shouldShowFirstSendTip)
    }

    /// Pill + FAB hide during search and when the feed chrome is scrolled away.
    private var showFloatingChrome: Bool {
        !homeSearchActive && !(tab == .feed && homeChromeCollapsed)
    }

    /// Ends editing app-wide — needed because Home stays mounted under other tabs.
    private func resignKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    @ViewBuilder
    private func composeView(for sheet: ComposeSheet) -> some View {
        switch sheet {
        case .launch(let request):
            ComposeView(
                editing: request.editingGratitude,
                initialRecipient: request.recipientName,
                initialRecipientProfile: request.profile,
                initialMessage: request.message,
                initialMessagePlaceholder: request.messagePlaceholder,
                initialImageFileName: request.imageFileName,
                inspiredByGratitudeId: request.inspiredByGratitudeId,
                inspiredByAuthorName: request.inspiredByAuthorName,
                campaignHint: request.campaignHint,
                campaignId: request.campaignId,
                campaignDay: request.campaignDay,
                analyticsSource: request.analyticsSource,
                allowsEmptyRecipient: request.allowsEmptyRecipient,
                opensOnShareScreen: request.opensOnShareScreen
            )
        }
    }

    @discardableResult
    private func presentPendingComposeIfNeeded() -> Bool {
        if ComposeLaunchBridge.shared.pending == nil {
            ComposeShareHandoff.applyPendingShare()
        }
        guard let request = ComposeLaunchBridge.shared.consume() else { return false }
        // Blank app_open / post_login. Other queued requests still present.
        guard !request.isWeakDefault else { return false }
        presentCompose(.launch(request))
        return true
    }

    /// Apply any queued compose / tab destinations from login, notifications,
    /// widgets, Siri, share, deep links, etc. Does **not** invent a blank
    /// compose on ordinary icon opens.
    private func presentLaunchSurfaces() {
        Task { @MainActor in
            await WatchVoiceDraftStore.restorePendingComposeIfNeeded()
            presentPendingComposeIfNeeded()
            presentPendingTabIfNeeded()
        }
    }

    /// Clears overlapping sheets/keyboard, then presents compose so it isn’t
    /// trapped at a half-height detent (e.g. share sheet still open when a
    /// streak notification opens compose).
    private func presentCompose(_ sheet: ComposeSheet) {
        showProfileSettings = false
        homeSearchActive = false
        homeChromeCollapsed = false
        resignKeyboard()
        NotificationCenter.default.post(name: .dismissTransientSheets, object: nil)

        // A deep link / notification compose is already waiting out the dismiss
        // delay. A weak app_open must not cancel it — that drops the launch and
        // never fires appreciation_form_started.
        if composeSheet == nil, composePresentInFlight, !composePresentIntentIsWeak, sheet.isWeakDefault {
            return
        }

        // Only wait when replacing an open cover — FAB / 30 Days taps should feel instant.
        let replacingOpenCover = composeSheet != nil
        if let current = composeSheet {
            // Calendar / notification prefills must replace blank app_open compose.
            guard Self.incomingBeatsOpenCompose(current: current, incoming: sheet) else { return }
            composeSheet = nil
        }

        composePresentIntentIsWeak = sheet.isWeakDefault
        composePresentGeneration += 1
        let generation = composePresentGeneration

        // FAB / 30 Days: present on this turn — no Task hop.
        if !replacingOpenCover {
            composePresentInFlight = false
            composeSheet = sheet
            return
        }

        // Replacing an open cover: wait for dismiss, then present again.
        composePresentInFlight = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard generation == composePresentGeneration else { return }
            if let current = composeSheet {
                guard Self.incomingBeatsOpenCompose(current: current, incoming: sheet) else {
                    composePresentInFlight = false
                    return
                }
            }
            composeSheet = sheet
            composePresentInFlight = false
        }
    }

    /// Richer launches (calendar email, share, Siri) beat blank / `app_open` compose.
    private static func incomingBeatsOpenCompose(current: ComposeSheet, incoming: ComposeSheet) -> Bool {
        guard !incoming.isWeakDefault else { return false }
        return current.isWeakDefault
    }

    private func presentPendingTabIfNeeded() {
        guard let destination = TabLaunchBridge.shared.consume() else { return }
        switch destination {
        case .feed, .home, .received:
            feedPath = NavigationPath()
            withAnimation(.easeInOut(duration: 0.18)) { tab = .feed }
            if destination == .received {
                // Let Home finish appearing before scrolling to pending thanks.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    NotificationCenter.default.post(name: .focusReceivedThanks, object: nil)
                }
            }
        case .notifications:
            notificationsPath = NavigationPath()
            withAnimation(.easeInOut(duration: 0.18)) { tab = .notifications }
        case .profileInspired:
            composeSheet = nil
            showProfileSettings = false
            profilePath = NavigationPath()
            withAnimation(.easeInOut(duration: 0.18)) { tab = .profile }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                NotificationCenter.default.post(name: .focusProfileInspired, object: nil)
            }
        }
    }

    /// Floating liquid-glass pill (Home / Bell / Profile) + trailing compose FAB.
    private var floatingChrome: some View {
        ZStack(alignment: .bottom) {
            HStack {
                Spacer(minLength: 0)
                tabPill
                Spacer(minLength: 0)
            }
            HStack {
                Spacer(minLength: 0)
                composeFAB
            }
            .padding(.horizontal, 18)
        }
        .padding(.bottom, 10)
    }

    private var tabPill: some View {
        HStack(spacing: 4) {
            tabItem(icon: "house.fill", label: "Home", value: .feed, iconOnly: true)
            tabItem(
                icon: "bell.fill",
                label: "Notifications",
                value: .notifications,
                badge: unreadCount,
                iconOnly: true
            )
            tabItem(icon: "person.fill", label: "Profile", value: .profile, iconOnly: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        // Solid fill — `.ultraThinMaterial` triggers `glassEffect()` every chrome
        // hide/show frame while scrolling and can freeze the Simulator UI.
        .background(Theme.surface.opacity(0.94), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.9), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 6)
    }

    private var composeFAB: some View {
        Button {
            if !hasSeenFirstSendTip {
                Analytics.capture("first_send_tip_tapped", ["via": "compose_fab"])
                hasSeenFirstSendTip = true
            }
            presentCompose(Self.tabComposeSheet())
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.onPrimary)
                .frame(width: 56, height: 56)
                .background(Theme.ctaGradient, in: Circle())
                .shadow(color: Theme.coral.opacity(0.5), radius: 12, y: 4)
        }
        // Default ButtonStyle fades the whole control ~60% — too ghostly for a FAB.
        .buttonStyle(ComposeFABButtonStyle())
        .accessibilityLabel("Send an appreciation")
    }

    private var firstSendTipOverlay: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(FirstSendTip.title)
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(FirstSendTip.detail)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Button {
                Analytics.capture("first_send_tip_dismissed")
                hasSeenFirstSendTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
        )
        .onTapGesture {
            Analytics.capture("first_send_tip_tapped", ["via": "tooltip"])
            hasSeenFirstSendTip = true
            presentCompose(
                .launch(
                    ComposeLaunchBridge.Request(
                        analyticsSource: "first_send_tip"
                    )
                )
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(FirstSendTip.title)
    }

    private func tabItem(
        icon: String,
        label: String,
        value: Tab,
        badge: Int = 0,
        iconOnly: Bool = false
    ) -> some View {
        Button {
            selectTab(value)
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, height: 40)
                        .overlay(alignment: .topTrailing) {
                            if badge > 0 {
                                Circle().fill(Theme.coral).frame(width: 8, height: 8)
                                    .offset(x: -6, y: 4)
                            }
                        }
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .overlay(alignment: .topTrailing) {
                                if badge > 0 {
                                    Circle().fill(Theme.coral).frame(width: 8, height: 8)
                                        .offset(x: 4, y: -2)
                                }
                            }
                        Text(label)
                            .font(Theme.body(10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(tab == value ? Theme.primary : Theme.textTertiary)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    /// Same as system tabs: tap another section to switch; re-tap the current
    /// section to pop back to its root (Home, Notifications, or Profile).
    private func selectTab(_ value: Tab) {
        resignKeyboard()
        homeSearchActive = false
        homeChromeCollapsed = false
        if tab == value {
            popToRoot(value)
            if value == .feed {
                appVisits.recordReturn()
                captureHomeRetap()
            }
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { tab = value }
    }

    /// Re-tapping Home is a view, and so is the first time it appears.
    private func captureHomeRetap() {
        guard appVisits.claimHomeView(force: true) else { return }
        Analytics.homeViewed(visitNumber: max(appVisits.number, 1), reason: "retap")
    }

    private func popToRoot(_ value: Tab) {
        switch value {
        case .feed:
            feedPath = NavigationPath()
            feedDetail = nil
        case .notifications:
            notificationsPath = NavigationPath()
            notificationDetail = nil
        case .profile:
            profilePath = NavigationPath()
            showProfileSettings = false
        }
    }

    private func refreshUnread() async {
        guard let userId = auth.userId else { return }
        let remote = (try? await GratitudeService.unreadNotificationCount(userId: userId)) ?? 0
        unreadCount = remote + CalendarThankSuggestionStore.unreadCount()
    }
}

/// Soft press for the compose FAB — keep coral solid; nudge scale instead of fading out.
private struct ComposeFABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    Circle().fill(Color.black.opacity(0.12))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
