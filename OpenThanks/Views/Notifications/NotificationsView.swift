import SwiftUI

struct NotificationsView: View {
    @Binding var path: NavigationPath
    @Binding var unreadCount: Int
    @Environment(AuthService.self) private var auth
    @State private var notes: [AppNotification] = []
    @State private var pendingCount = 0
    @State private var loading = true
    @State private var markingAll = false

    private var hasUnread: Bool {
        notes.contains { $0.read != true }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if loading && notes.isEmpty && pendingCount == 0 {
                    ProgressView().tint(Theme.coral)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if pendingCount > 0 {
                                PendingAppreciationsBanner(count: pendingCount)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 12)
                                    .padding(.bottom, 8)
                            }

                            if notes.isEmpty {
                                emptyState
                                    .padding(.top, pendingCount > 0 ? 24 : 80)
                            } else {
                                ForEach(notes) { note in
                                    row(note)
                                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                                        .padding(.leading, 68)
                                }
                            }
                        }
                        .padding(.bottom, 96)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if hasUnread {
                        Button {
                            Task { await markAllRead() }
                        } label: {
                            if markingAll {
                                ProgressView().controlSize(.small).tint(Theme.coral)
                            } else {
                                Text("Mark all read")
                                    .font(Theme.body(14, weight: .semibold))
                                    .foregroundStyle(Theme.coral)
                            }
                        }
                        .disabled(markingAll)
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .appDestinations()
        }
    }


    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textTertiary)
            Text("When someone sends, accepts, or hearts an appreciation, you'll see it here.")
                .font(Theme.body(14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    /// Each notification opens the post it's about; the avatar opens
    /// that person's profile.
    @ViewBuilder
    private func row(_ note: AppNotification) -> some View {
        let unread = note.read != true
        HStack(spacing: 12) {
            ProfileAvatarLink(profile: note.fromUser, size: 44)
            Group {
                if let gratitudeId = note.gratitudeId {
                    NavigationLink(value: GratitudeIdRoute(id: gratitudeId)) {
                        rowContent(note, linksToPost: true)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded {
                        Task { await markRead(note) }
                    })
                } else {
                    Button {
                        Task { await markRead(note) }
                    } label: {
                        rowContent(note, linksToPost: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(unread ? Theme.coral.opacity(0.06) : Color.clear)
    }

    private func rowContent(_ note: AppNotification, linksToPost: Bool) -> some View {
        let unread = note.read != true
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: note))
                    .font(Theme.body(15, weight: unread ? .semibold : .regular))
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
            if unread {
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

    private func displayName(for note: AppNotification) -> String {
        if let name = note.fromUser?.displayName { return name }
        if note.type == "gratitude_friday" { return "OpenThanks" }
        return "Someone"
    }

    private func load() async {
        guard let userId = auth.userId else { return }
        // Only show the full-screen spinner on first load.
        if notes.isEmpty { loading = true }
        async let notesTask = GratitudeService.notifications(userId: userId)
        async let pendingTask = GratitudeService.pendingCount(authorId: userId)

        do {
            let result = try await notesTask
            withAnimation(.easeInOut(duration: 0.2)) {
                notes = result
            }
            syncUnread()
        } catch {
            if !error.isCancellation { /* keep existing */ }
        }

        pendingCount = (try? await pendingTask) ?? pendingCount
        loading = false
    }

    private func markRead(_ note: AppNotification) async {
        guard note.read != true,
              let idx = notes.firstIndex(where: { $0.id == note.id }) else { return }
        notes[idx].read = true
        syncUnread()
        try? await GratitudeService.markRead(id: note.id)
    }

    private func markAllRead() async {
        guard let userId = auth.userId, hasUnread else { return }
        markingAll = true
        for i in notes.indices where notes[i].read != true {
            notes[i].read = true
        }
        syncUnread()
        try? await GratitudeService.markAllRead(userId: userId)
        markingAll = false
    }

    private func syncUnread() {
        unreadCount = notes.filter { $0.read != true }.count
    }
}
