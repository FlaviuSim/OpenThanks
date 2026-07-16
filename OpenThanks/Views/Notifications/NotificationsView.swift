import SwiftUI

struct NotificationsView: View {
    @Binding var unreadCount: Int
    @Environment(AuthService.self) private var auth
    @State private var notes: [AppNotification] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading && notes.isEmpty {
                    ProgressView().tint(Theme.coral)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if notes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell")
                            .font(.system(size: 36))
                            .foregroundStyle(Theme.textTertiary)
                        Text("When someone reacts to your appreciation, you'll see it here.")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(notes) { note in
                                row(note)
                                Rectangle().fill(Theme.hairline).frame(height: 0.5)
                                    .padding(.leading, 68)
                            }
                        }
                        .padding(.bottom, 96)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .appDestinations()
        }
    }

    /// Each notification opens the post it's about; the avatar opens
    /// that person's profile.
    @ViewBuilder
    private func row(_ note: AppNotification) -> some View {
        HStack(spacing: 12) {
            ProfileAvatarLink(profile: note.fromUser, size: 44)
            Group {
                if let gratitudeId = note.gratitudeId {
                    NavigationLink(value: GratitudeIdRoute(id: gratitudeId)) {
                        rowContent(note, linksToPost: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    rowContent(note, linksToPost: false)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func rowContent(_ note: AppNotification, linksToPost: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.fromUser?.displayName ?? "Someone")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(note.verb)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            .multilineTextAlignment(.leading)
            Spacer()
            if let date = note.createdAt {
                Text(date, format: .relative(presentation: .named))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            if note.read != true {
                Circle().fill(Theme.coral).frame(width: 8, height: 8)
            }
            if linksToPost {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private func load() async {
        guard let userId = auth.userId else { return }
        loading = true
        notes = (try? await GratitudeService.notifications(userId: userId)) ?? []
        unreadCount = 0
        try? await GratitudeService.markAllRead(userId: userId)
        loading = false
    }
}
