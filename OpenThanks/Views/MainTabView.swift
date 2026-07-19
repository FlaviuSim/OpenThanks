import SwiftUI

struct MainTabView: View {
    enum Tab { case feed, notifications, profile }

    @State private var tab: Tab = .feed
    @State private var showCompose = false
    @State private var unreadCount = 0
    @State private var feedPath = NavigationPath()
    @State private var notificationsPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var showProfileSettings = false
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keep all tabs mounted so switching is instant and images stay cached.
            FeedView(path: $feedPath)
                .opacity(tab == .feed ? 1 : 0)
                .allowsHitTesting(tab == .feed)
                .zIndex(tab == .feed ? 1 : 0)

            NotificationsView(path: $notificationsPath, unreadCount: $unreadCount)
                .opacity(tab == .notifications ? 1 : 0)
                .allowsHitTesting(tab == .notifications)
                .zIndex(tab == .notifications ? 1 : 0)

            ProfileView(path: $profilePath, showSettings: $showProfileSettings)
                .opacity(tab == .profile ? 1 : 0)
                .allowsHitTesting(tab == .profile)
                .zIndex(tab == .profile ? 1 : 0)

            tabBar
                .zIndex(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .syncAppAppearance()
        .fullScreenCover(isPresented: $showCompose) {
            ComposeView()
                .syncAppAppearance()
        }
        .task { await refreshUnread() }
        .animation(.easeInOut(duration: 0.18), value: tab)
    }

    private var tabBar: some View {
        HStack {
            tabItem(icon: "house.fill", label: "Home", value: .feed)
            Spacer()
            Button { showCompose = true } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Theme.ctaGradient, in: Circle())
                    .shadow(color: Theme.coral.opacity(0.5), radius: 12, y: 4)
            }
            .offset(y: -12)
            Spacer()
            tabItem(icon: "bell.fill", label: "Notifications", value: .notifications,
                    badge: unreadCount)
            tabItem(icon: "person.fill", label: "Profile", value: .profile)
        }
        .padding(.horizontal, 28)
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
                Text(label).font(Theme.body(10, weight: .medium))
            }
            .foregroundStyle(tab == value ? Theme.coral : Theme.textTertiary)
            .frame(width: 66)
        }
    }

    private func selectTab(_ value: Tab) {
        if tab == value {
            popToRoot(value)
            return
        }
        withAnimation(.easeInOut(duration: 0.18)) { tab = value }
    }

    /// Re-tapping the active tab returns to that tab's root screen.
    private func popToRoot(_ value: Tab) {
        switch value {
        case .feed:
            feedPath = NavigationPath()
        case .notifications:
            notificationsPath = NavigationPath()
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
