import SwiftUI

struct FeedView: View {
    enum Scope: String, CaseIterable { case personal = "Personal", world = "World" }

    @Environment(AuthService.self) private var auth
    @State private var scope: Scope = .personal
    @State private var items: [Gratitude] = []
    @State private var pendingToAccept: [Gratitude] = []
    @State private var pendingSentCount = 0
    @State private var heartedIds: Set<UUID> = []
    @State private var loading = true
    @State private var error: String?
    @State private var showCompose = false

    private var isEmpty: Bool { items.isEmpty && pendingToAccept.isEmpty }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                picker
                if pendingSentCount > 0 {
                    PendingAppreciationsBanner(count: pendingSentCount)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                content
            }
            .background(Theme.background)
            .task(id: scope) { await load() }
            .refreshable { await load() }
            .onAppear { Task { await refreshPendingSentCount() } }
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations()
            .fullScreenCover(isPresented: $showCompose) {
                ComposeView()
                    .syncAppAppearance()
            }
            .syncAppAppearance()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.heartGradient)
            Text("OpenThanks")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { showCompose = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Thank someone")
                        .font(Theme.body(13, weight: .semibold))
                }
                .foregroundStyle(Color(hex: 0x2B1209))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.ctaGradient, in: Capsule())
                .shadow(color: Theme.coral.opacity(0.35), radius: 8, y: 2)
            }
            .accessibilityLabel("Thank someone — share an appreciation")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(Scope.allCases, id: \.self) { s in
                Button(s.rawValue) { scope = s }
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(scope == s ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(scope == s ? Theme.surfaceRaised : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if loading && isEmpty {
            Spacer(); ProgressView().tint(Theme.coral); Spacer()
        } else if let error, isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Text("Couldn't load Home").font(Theme.body(16, weight: .semibold))
                Text(error).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                Button("Try again") { Task { await load() } }
                    .foregroundStyle(Theme.coral)
            }
            .padding(24)
            Spacer()
        } else if isEmpty {
            Spacer()
            VStack(spacing: 12) {
                HeartMark(size: 48)
                Text(scope == .personal
                     ? "No appreciations yet. Send your first one."
                     : "Nothing public yet — be the first.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if !pendingToAccept.isEmpty {
                        pendingHeader
                        ForEach(pendingToAccept) { item in
                            AcceptPendingCard(
                                gratitude: item,
                                onAccepted: { accepted in
                                    pendingToAccept.removeAll { $0.id == accepted.id }
                                    if !items.contains(where: { $0.id == accepted.id }) {
                                        items.insert(accepted, at: 0)
                                    }
                                },
                                onDeclined: { id in
                                    pendingToAccept.removeAll { $0.id == id }
                                }
                            )
                        }
                    }

                    ForEach(items) { item in
                        GratitudeCard(gratitude: item,
                                      isHearted: heartedIds.contains(item.id),
                                      onHeart: { toggleHeart(item) })
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
        }
    }

    private var pendingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pendingToAccept.count == 1
                 ? "1 appreciation waiting for you"
                 : "\(pendingToAccept.count) appreciations waiting for you")
                .font(Theme.display(18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Accept to add them to your profile and the feed.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func refreshPendingSentCount() async {
        guard let userId = auth.userId else { return }
        pendingSentCount = (try? await GratitudeService.pending(authorId: userId))?.count ?? pendingSentCount
    }

    private func load() async {
        guard let userId = auth.userId else { return }
        loading = true; error = nil
        do {
            async let feedTask: [Gratitude] = scope == .personal
                ? GratitudeService.personalFeed(userId: userId)
                : GratitudeService.worldFeed()
            async let pendingTask: [Gratitude] = GratitudeService.pendingToAccept(
                userId: userId,
                email: auth.currentProfile?.email,
                phone: auth.currentProfile?.phone
            )
            async let pendingSentTask: [Gratitude] = GratitudeService.pending(authorId: userId)

            let result = try await feedTask
            let pending = (try? await pendingTask) ?? []
            let pendingSent = (try? await pendingSentTask) ?? []
            let hearts = try await GratitudeService.myHearts(userId: userId,
                                                            among: result.map(\.id))
            items = result
            pendingToAccept = pending
            pendingSentCount = pendingSent.count
            heartedIds = hearts
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }

    private func toggleHeart(_ item: Gratitude) {
        guard let userId = auth.userId else { return }
        let wasHearted = heartedIds.contains(item.id)
        // Optimistic update
        if wasHearted { heartedIds.remove(item.id) } else { heartedIds.insert(item.id) }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            let delta = wasHearted ? -1 : 1
            items[idx].hearts = [CountHolder(count: max(0, item.heartCount + delta))]
        }
        Task {
            do {
                if wasHearted {
                    try await GratitudeService.unheart(gratitudeId: item.id, userId: userId)
                } else {
                    try await GratitudeService.heart(gratitudeId: item.id, userId: userId, authorId: item.authorId)
                }
            } catch {
                // Revert on failure
                if wasHearted { heartedIds.insert(item.id) } else { heartedIds.remove(item.id) }
            }
        }
    }
}

struct GratitudeCard: View {
    let gratitude: Gratitude
    let isHearted: Bool
    let onHeart: () -> Void

    @State private var fullScreenImageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProfileAvatarLink(profile: gratitude.author, size: 38)
                NavigationLink(value: gratitude) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            (Text(gratitude.author?.displayName ?? "Someone")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                             + Text(" thanked ").font(Theme.body(15)).foregroundStyle(Theme.textSecondary)
                             + Text(gratitude.recipientDisplayName)
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            if let date = gratitude.createdAt {
                                Text(date, format: .relative(presentation: .named))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            NavigationLink(value: gratitude) {
                Text(gratitude.message)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if let url = gratitude.mediaURL, gratitude.mediaType?.hasPrefix("video") != true {
                Button { fullScreenImageURL = url } label: {
                    FlexiblePostImage(url: url, maxHeight: 420)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 18) {
                Button(action: onHeart) {
                    HStack(spacing: 5) {
                        Image(systemName: isHearted ? "heart.fill" : "heart")
                            .foregroundStyle(isHearted ? Theme.coral : Theme.textSecondary)
                        Text("\(gratitude.heartCount)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.body(14, weight: .medium))
                }
                Spacer()
                if gratitude.visibility == .private {
                    Label("Private", systemImage: "lock.fill")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .card()
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
    }
}

struct AvatarView: View {
    let profile: Profile?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = profile?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Theme.surfaceRaised)
            Text(String((profile?.displayName ?? "?").prefix(1)).uppercased())
                .font(Theme.body(size * 0.42, weight: .semibold))
                .foregroundStyle(Theme.coralLight)
        }
    }
}
