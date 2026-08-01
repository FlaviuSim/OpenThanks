import SwiftUI

struct NotificationsView: View {
    @Binding var path: NavigationPath
    @Binding var unreadCount: Int
    var isSelected = true
    /// When set (iPad sidebar shell), post taps fill the detail pane instead of pushing.
    var splitSelection: Binding<GratitudeIdRoute?>? = nil
    @Environment(AuthService.self) private var auth
    @State private var notes: [AppNotification] = []
    @State private var pendingCount = 0
    @State private var loading = true
    @State private var markingAll = false

    private var hasUnread: Bool {
        notes.contains { $0.read != true }
    }

    private var usesSplitDetail: Bool { splitSelection != nil }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if usesSplitDetail {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            listChrome
                                .frame(width: listPaneWidth(for: geo.size.width))
                            Rectangle()
                                .fill(Theme.hairline)
                                .frame(width: 0.5)
                                .ignoresSafeArea()
                            detailPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    listChrome
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
            .onChange(of: isSelected) { _, selected in
                if selected { Task { await load() } }
            }
            .refreshable { await load() }
            .appDestinations()
            .environment(\.openProfile) { path.append($0) }
        }
    }

    private func listPaneWidth(for total: CGFloat) -> CGFloat {
        min(420, max(320, total * 0.4))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let route = splitSelection?.wrappedValue {
            GratitudeLoaderView(
                gratitudeId: route.id,
                onOpenProfile: { path.append($0) }
            )
        } else {
            ContentUnavailableView(
                "Select a notification",
                systemImage: "bell",
                description: Text("Choose a notification to open the appreciation here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
    }

    private var listChrome: some View {
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
                    .tabChromeBottomPadding()
                    .readableWidth()
                }
            }
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
        let selected = usesSplitDetail
            && note.gratitudeId != nil
            && splitSelection?.wrappedValue?.id == note.gratitudeId
        HStack(spacing: 12) {
            ProfileAvatarLink(
                profile: note.fromUser,
                size: 44,
                onOpen: { path.append($0) }
            )
            Group {
                if note.type == "gratitude_friday" {
                    Button {
                        Task {
                            await markRead(note)
                            ComposeLaunchBridge.shared.queue(analyticsSource: "notification_friday_tap")
                        }
                    } label: {
                        rowContent(note, linksToPost: true)
                    }
                    .buttonStyle(.plain)
                } else if note.type == "pay_it_forward_reminder" {
                    Button {
                        Task {
                            await markRead(note)
                            ComposeLaunchBridge.shared.queue(analyticsSource: "notification_pay_it_forward")
                        }
                    } label: {
                        rowContent(note, linksToPost: true)
                    }
                    .buttonStyle(.plain)
                } else if let gratitudeId = note.gratitudeId {
                    if usesSplitDetail {
                        Button {
                            Task { await markRead(note) }
                            splitSelection?.wrappedValue = GratitudeIdRoute(id: gratitudeId)
                        } label: {
                            rowContent(note, linksToPost: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(value: GratitudeIdRoute(id: gratitudeId)) {
                            rowContent(note, linksToPost: true)
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(TapGesture().onEnded {
                            Task { await markRead(note) }
                        })
                    }
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
        .background(selected ? Theme.coral.opacity(0.12) : (unread ? Theme.coral.opacity(0.06) : Color.clear))
    }

    private func rowContent(_ note: AppNotification, linksToPost: Bool) -> some View {
        let unread = note.read != true
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: note))
                    .font(Theme.body(15, weight: unread ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
                Text(note.displayVerb)
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
        if note.type == "gratitude_friday"
            || note.type == "pay_it_forward_reminder"
            || note.type == "competition_winner" {
            return "OpenThanks"
        }
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
