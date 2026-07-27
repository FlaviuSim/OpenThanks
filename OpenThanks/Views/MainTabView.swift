import SwiftUI
import UIKit

struct MainTabView: View {
    enum Tab: Hashable { case feed, notifications, profile }

    private enum ComposeSheet: Identifiable {
        case blank
        case launch(ComposeLaunchBridge.Request)

        var id: String {
            switch self {
            case .blank: "blank"
            case .launch(let request): request.id.uuidString
            }
        }
    }

    @State private var tab: Tab = .feed
    @State private var composeSheet: ComposeSheet?
    @State private var unreadCount = 0
    @State private var feedPath = NavigationPath()
    @State private var notificationsPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var showProfileSettings = false
    /// Home people-search is focused — hide the tab bar (native search-mode UX).
    @State private var homeSearchActive = false
    /// Selected post for iPad list↔detail on Home.
    @State private var feedDetail: Gratitude?
    /// Selected notification route for iPad list↔detail.
    @State private var notificationDetail: GratitudeIdRoute?
    @Environment(AuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("fridayGratitudeReminderEnabled") private var fridayReminderEnabled = true
    @AppStorage("calendarGratitudeNudgeEnabled") private var calendarNudgeEnabled = true

    private var usesSidebar: Bool { sizeClass == .regular }

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
        .composeCover(item: $composeSheet) { sheet in
            composeView(for: sheet)
        }
        .task { await refreshUnread() }
        .onAppear {
            presentPendingComposeIfNeeded()
            presentPendingTabIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .composeLaunchQueued)) { _ in
            presentPendingComposeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tabLaunchQueued)) { _ in
            presentPendingTabIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            presentPendingComposeIfNeeded()
            presentPendingTabIfNeeded()
            if fridayReminderEnabled {
                Task { await NotificationService.refreshFridayReminderIfEnabled(true) }
            }
            if calendarNudgeEnabled {
                Task {
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
        .animation(.easeInOut(duration: 0.2), value: homeSearchActive)
        .onChange(of: tab) { _, newTab in
            if newTab != .feed {
                homeSearchActive = false
                resignKeyboard()
            }
            // Keep list↔detail selection when switching tabs so return feels continuous.
        }
        .onReceive(NotificationCenter.default.publisher(for: .gratitudeAccepted)) { _ in
            // Fallback if pay-it-forward isn't shown; delayed so it stays gentle.
            AppStoreReviewPrompt.scheduleAfterReceivingAppreciation()
        }
        .onChange(of: composeSheet != nil) { _, open in
            if open {
                homeSearchActive = false
                resignKeyboard()
            }
        }
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
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Theme.coral, in: Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                    }
                    .foregroundStyle(tab == .notifications ? Theme.coral : Theme.textPrimary)
                    .listRowBackground(tab == .notifications ? Theme.coral.opacity(0.12) : Color.clear)

                    sidebarRow(title: "Profile", systemImage: "person.fill", value: .profile)
                }

                Section {
                    Button {
                        resignKeyboard()
                        homeSearchActive = false
                        composeSheet = .blank
                    } label: {
                        Label("Thank someone", systemImage: "heart.fill")
                            .foregroundStyle(Theme.coral)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("OpenThanks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        composeSheet = .blank
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Thank someone")
                }
            }
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func sidebarRow(title: String, systemImage: String, value: Tab) -> some View {
        Button {
            selectTab(value)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .foregroundStyle(tab == value ? Theme.coral : Theme.textPrimary)
        .listRowBackground(tab == value ? Theme.coral.opacity(0.12) : Color.clear)
    }

    /// Keep stacks mounted (like phone) so tab switches stay instant and image cache survives.
    private var detailColumn: some View {
        ZStack {
            FeedView(
                path: $feedPath,
                isSelected: tab == .feed,
                searchActive: $homeSearchActive,
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
        ZStack(alignment: .bottom) {
            FeedView(
                path: $feedPath,
                isSelected: tab == .feed,
                searchActive: $homeSearchActive
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

            if !homeSearchActive {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
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
        case .blank:
            ComposeView(analyticsSource: "tab_compose")
        case .launch(let request):
            ComposeView(
                initialRecipient: request.recipientName,
                initialRecipientProfile: request.profile,
                initialMessage: request.message,
                initialImageFileName: request.imageFileName,
                analyticsSource: request.analyticsSource
            )
        }
    }

    private func presentPendingComposeIfNeeded() {
        if ComposeLaunchBridge.shared.pending == nil {
            ComposeShareHandoff.applyPendingShare()
        }
        guard let request = ComposeLaunchBridge.shared.consume() else { return }
        composeSheet = .launch(request)
    }

    private func presentPendingTabIfNeeded() {
        guard let destination = TabLaunchBridge.shared.consume() else { return }
        switch destination {
        case .feed, .home, .received:
            feedPath = NavigationPath()
            withAnimation(.easeInOut(duration: 0.18)) { tab = .feed }
            if destination == .received {
                NotificationCenter.default.post(name: .focusReceivedThanks, object: nil)
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(icon: "house.fill", label: "Home", value: .feed)
                .frame(maxWidth: .infinity)

            Button {
                resignKeyboard()
                homeSearchActive = false
                composeSheet = .blank
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ctaGradient, in: Circle())
                    .shadow(color: Theme.coral.opacity(0.5), radius: 12, y: 4)
            }
            .offset(y: -12)
            .frame(width: 72)

            tabItem(icon: "bell.fill", label: "Notifications", value: .notifications,
                    badge: unreadCount)
                .frame(maxWidth: .infinity)

            tabItem(icon: "person.fill", label: "Profile", value: .profile)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func tabItem(icon: String, label: String, value: Tab, badge: Int = 0) -> some View {
        Button {
            selectTab(value)
        } label: {
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
            .foregroundStyle(tab == value ? Theme.coral : Theme.textTertiary)
            .frame(maxWidth: .infinity)
        }
    }

    private func selectTab(_ value: Tab) {
        resignKeyboard()
        homeSearchActive = false
        if tab == value {
            popToRoot(value)
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { tab = value }
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
        unreadCount = (try? await GratitudeService.unreadNotificationCount(userId: userId)) ?? unreadCount
    }
}
