import SwiftUI

struct MainTabView: View {
    enum Tab { case feed, notifications, profile }

    @State private var tab: Tab = .feed
    @State private var showCompose = false
    @State private var unreadCount = 0
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .feed: FeedView()
                case .notifications: NotificationsView(unreadCount: $unreadCount)
                case .profile: ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
        .background(Theme.background)
        .syncAppAppearance()
        .fullScreenCover(isPresented: $showCompose) {
            ComposeView()
                .syncAppAppearance()
        }
        .task { await refreshUnread() }
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
            tab = value
            if value != .notifications {
                Task { await refreshUnread() }
            }
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

    private func refreshUnread() async {
        guard let userId = auth.userId else { return }
        let notes = (try? await GratitudeService.notifications(userId: userId, limit: 50)) ?? []
        unreadCount = notes.filter { $0.read != true }.count
    }
}
