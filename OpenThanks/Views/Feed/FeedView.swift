import SwiftUI

struct FeedView: View {
    enum Scope: String, CaseIterable { case personal = "Personal", world = "World" }

    @Binding var path: NavigationPath
    @Environment(AuthService.self) private var auth
    @State private var scope: Scope = .personal
    @State private var items: [Gratitude] = []
    @State private var pendingToAccept: [Gratitude] = []
    /// Ids the user already accepted/declined this session — keeps pull-to-refresh
    /// from resurrecting a card when a stale pending query races the accept write.
    @State private var resolvedPendingIds: Set<UUID> = []
    @State private var pendingSentCount = 0
    @State private var heartedIds: Set<UUID> = []
    @State private var loading = true
    @State private var error: String?
    @State private var showCompose = false
    @State private var composeRecipient: String?
    /// Once per session: if Personal has nothing, land on World instead.
    @State private var didAutoSwitchToWorld = false
    @State private var scrollToPendingToken = 0
    @State private var loadGeneration = 0

    private var isEmpty: Bool { items.isEmpty && pendingToAccept.isEmpty }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                HomeProfileSearch(
                    onSelect: { profile in
                        path.append(profile)
                    },
                    onInvite: { name in
                        composeRecipient = name
                        showCompose = true
                    }
                )
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .zIndex(2)

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
            .toolbar(.hidden, for: .navigationBar)
            .appDestinations()
            .fullScreenCover(isPresented: $showCompose) {
                ComposeView(initialRecipient: composeRecipient)
                    .syncAppAppearance()
            }
            .onChange(of: showCompose) { _, open in
                if !open { composeRecipient = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusReceivedThanks)) { _ in
                scrollToPendingToken += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .gratitudeAccepted)) { note in
                guard let gratitude = note.object as? Gratitude else { return }
                applyAcceptedPending(gratitude)
            }
            .syncAppAppearance()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.heartGradient)
                Text("OpenThanks")
                    .font(Theme.display(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                composeRecipient = nil
                showCompose = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("Thank someone")
                        .font(Theme.body(13, weight: .semibold))
                        .lineLimit(1)
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
                Button(s.rawValue) {
                    withAnimation(.easeInOut(duration: 0.2)) { scope = s }
                }
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(scope == s ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(scope == s ? Theme.surfaceRaised : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if !pendingToAccept.isEmpty {
                            pendingHeader
                                .id("pendingThanks")
                            ForEach(pendingToAccept) { item in
                                AcceptPendingCard(
                                    gratitude: item,
                                    onAccepted: { accepted in
                                        applyAcceptedPending(accepted)
                                    },
                                    onDeclined: { id in
                                        resolvedPendingIds.insert(id)
                                        pendingToAccept.removeAll { $0.id == id }
                                        Task { await refreshWidgetSnapshot() }
                                    },
                                    onFailed: { gratitude in
                                        resolvedPendingIds.remove(gratitude.id)
                                        if !pendingToAccept.contains(where: { $0.id == gratitude.id }) {
                                            pendingToAccept.insert(gratitude, at: 0)
                                        }
                                        items.removeAll { $0.id == gratitude.id }
                                        Task { await refreshWidgetSnapshot() }
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
                    .opacity(loading && !isEmpty ? 0.72 : 1)
                    .animation(.easeInOut(duration: 0.2), value: loading)
                }
                .onChange(of: scrollToPendingToken) { _, _ in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("pendingThanks", anchor: .top)
                    }
                }
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

    private func applyAcceptedPending(_ gratitude: Gratitude) {
        resolvedPendingIds.insert(gratitude.id)
        pendingToAccept.removeAll { $0.id == gratitude.id }
        if gratitude.status == .accepted {
            if let idx = items.firstIndex(where: { $0.id == gratitude.id }) {
                items[idx] = gratitude
            } else {
                items.insert(gratitude, at: 0)
            }
            items.sort { $0.acceptanceSortDate > $1.acceptanceSortDate }
        }
        Task { await refreshWidgetSnapshot() }
    }

    private func applyPendingList(_ pending: [Gratitude]) {
        // Drop anything this session already resolved, then prune ids the server
        // no longer returns as pending (accept landed).
        let filtered = pending.filter { !resolvedPendingIds.contains($0.id) }
        resolvedPendingIds = Set(resolvedPendingIds.filter { id in
            pending.contains(where: { $0.id == id })
        })
        pendingToAccept = filtered
    }

    private func load() async {
        guard let userId = auth.userId else { return }
        // Keep prior content visible while refreshing / switching scope.
        loadGeneration += 1
        let generation = loadGeneration
        loading = true
        error = nil
        do {
            async let feedTask: [Gratitude] = scope == .personal
                ? GratitudeService.personalFeed(userId: userId)
                : GratitudeService.worldFeed()
            async let pendingTask: [Gratitude] = GratitudeService.pendingToAccept(
                userId: userId,
                email: auth.currentProfile?.email,
                phone: auth.currentProfile?.phone
            )
            async let pendingSentTask = GratitudeService.pendingCount(authorId: userId)

            let result = try await feedTask
            let pending = (try? await pendingTask) ?? []
            let pendingSent = (try? await pendingSentTask) ?? pendingSentCount

            guard generation == loadGeneration else { return }

            // Attach recipient + pending notification as soon as we see them —
            // don't wait until accept/decline (which used to create the notice).
            for item in pending where !resolvedPendingIds.contains(item.id) {
                await GratitudeService.ensurePendingRecipientLinked(item, userId: userId)
            }

            guard generation == loadGeneration else { return }

            // Empty personal feed → show World so Home isn't a blank screen.
            if scope == .personal, result.isEmpty, !didAutoSwitchToWorld {
                didAutoSwitchToWorld = true
                applyPendingList(pending)
                pendingSentCount = pendingSent
                loading = false
                withAnimation(.easeInOut(duration: 0.2)) { scope = .world }
                return
            }

            async let heartsTask = GratitudeService.myHearts(userId: userId, among: result.map(\.id))
            let hearts = (try? await heartsTask) ?? heartedIds

            guard generation == loadGeneration else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                items = result
                applyPendingList(pending)
                pendingSentCount = pendingSent
                heartedIds = hearts
            }
            await refreshWidgetSnapshot()
        } catch {
            if !error.isCancellation {
                self.error = error.localizedDescription
            }
        }
        if generation == loadGeneration {
            loading = false
        }
    }

    private func refreshWidgetSnapshot() async {
        guard let userId = auth.userId else { return }
        await WidgetSnapshotRefresher.refresh(
            displayName: auth.currentProfile?.displayName,
            userId: userId,
            email: auth.currentProfile?.email,
            phone: auth.currentProfile?.phone,
            pendingToAccept: pendingToAccept.count
        )
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
                            if let date = gratitude.displayDate {
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
                CachedAsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initials
                }
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

// MARK: - Home people search

/// Compact people search under the Home brand row — opens profiles or invites
/// someone who isn't on OpenThanks yet (matches the web home search).
private struct HomeProfileSearch: View {
    var onSelect: (Profile) -> Void
    var onInvite: (String) -> Void

    @State private var query = ""
    @State private var results: [Profile] = []
    @State private var searching = false
    @State private var didSearch = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showResults: Bool {
        focused && trimmed.count >= 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField

            if showResults {
                resultsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showResults)
        .animation(.easeInOut(duration: 0.18), value: results.map(\.id))
        .task(id: trimmed) {
            await runSearch(for: trimmed)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(focused ? Theme.coral : Theme.textTertiary)

            TextField("Search people by name", text: $query)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.search)

            if !query.isEmpty {
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Theme.coral.opacity(0.45) : Theme.hairline, lineWidth: 1)
        )
    }

    private var resultsPanel: some View {
        VStack(spacing: 0) {
            if searching && results.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.coral).controlSize(.small)
                    Text("Searching…")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(14)
            } else if !results.isEmpty {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, profile in
                    Button {
                        focused = false
                        onSelect(profile)
                        clear()
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(profile: profile, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                    .font(Theme.body(15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                if !profile.username.isEmpty {
                                    Text("@\(profile.username)")
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                } else if let headline = profile.headline, !headline.isEmpty {
                                    Text(headline)
                                        .font(Theme.body(13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < results.count - 1 {
                        Rectangle()
                            .fill(Theme.hairline)
                            .frame(height: 0.5)
                            .padding(.leading, 66)
                    }
                }
            } else if didSearch {
                VStack(spacing: 12) {
                    Text("No one named “\(trimmed)” yet")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Button {
                        focused = false
                        onInvite(trimmed)
                        clear()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Thank \(trimmed)")
                                .font(Theme.body(14, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: 0x2B1209))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.ctaGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Text("We’ll help you send them an appreciation.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
    }

    private func clear() {
        query = ""
        results = []
        searching = false
        didSearch = false
        focused = false
    }

    private func runSearch(for current: String) async {
        guard current.count >= 2 else {
            results = []
            searching = false
            didSearch = false
            return
        }

        searching = true
        didSearch = false
        try? await Task.sleep(for: .milliseconds(280))
        guard !Task.isCancelled else { return }

        do {
            let found = try await GratitudeService.searchProfiles(query: current)
            guard !Task.isCancelled else { return }
            results = found
            didSearch = true
        } catch {
            if !error.isCancellation {
                results = []
                didSearch = true
            }
        }
        searching = false
    }
}
