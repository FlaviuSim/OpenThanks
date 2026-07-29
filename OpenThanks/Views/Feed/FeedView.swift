import SwiftUI

struct FeedView: View {
    enum Scope: String, CaseIterable { case personal = "Personal", world = "World" }

    @Binding var path: NavigationPath
    /// False when another tab is showing — Home stays mounted, so clear search focus.
    var isSelected: Bool = true
    /// Mirrors search focus so the tab bar can hide during search (native search-mode).
    @Binding var searchActive: Bool
    /// When set (iPad sidebar shell), card taps fill the detail column instead of pushing.
    var splitSelection: Binding<Gratitude?>? = nil
    @Environment(AuthService.self) private var auth
    @State private var scope: Scope = .personal
    @State private var items: [Gratitude] = []
    @State private var pendingToAccept: [Gratitude] = []
    /// Ids the user already accepted/declined this session — keeps pull-to-refresh
    /// from resurrecting a card when a stale pending query races the accept write.
    @State private var resolvedPendingIds: Set<UUID> = []
    /// Bumped when a failed accept re-inserts a card so SwiftUI doesn't reuse
    /// stuck "Accepting…" @State from the previous attempt.
    @State private var pendingCardEpoch: [UUID: Int] = [:]
    @State private var pendingSentCount = 0
    @State private var heartedIds: Set<UUID> = []
    @State private var loading = true
    @State private var error: String?
    @State private var showCompose = false
    @State private var composeRecipient: String?
    @State private var composeAnalyticsSource = "home_thank_someone"
    /// After accepting, gently invite the recipient to thank someone else.
    @State private var payItForwardFromName: String?
    @State private var payItForwardPresentedIds: Set<UUID> = []
    /// Once per session: if Personal has nothing, land on World instead.
    @State private var didAutoSwitchToWorld = false
    @State private var scrollToPendingToken = 0
    @State private var loadGeneration = 0
    @FocusState private var searchFocused: Bool

    private var isEmpty: Bool { items.isEmpty && pendingToAccept.isEmpty }
    private var usesSplitDetail: Bool { splitSelection != nil }
    private var showPayItForward: Binding<Bool> {
        Binding(
            get: { payItForwardFromName != nil },
            set: { if !$0 { payItForwardFromName = nil } }
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if usesSplitDetail {
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            feedChrome
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
                    feedChrome
                }
            }
            .background(Theme.background)
            // Dismiss search keyboard when the user scrolls/drags anywhere on Home.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    dismissSearchKeyboard()
                }
            )
            .task(id: scope) { await load() }
            .refreshable { await load() }
            // Keep the bar hidden on the Home root; show it when a profile/post is pushed
            // so Back works (especially important on iPad two-pane).
            .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .appDestinations()
            .composeCover(isPresented: $showCompose) {
                ComposeView(
                    initialRecipient: composeRecipient,
                    analyticsSource: composeAnalyticsSource
                )
            }
            .sheet(isPresented: showPayItForward) {
                PayItForwardSheet(
                    fromName: payItForwardFromName,
                    onThankSomeone: {
                        composeRecipient = nil
                        composeAnalyticsSource = "post_accept_pay_it_forward"
                        Analytics.capture("pay_it_forward_tapped", ["source": "feed_accept"])
                        showCompose = true
                    }
                )
                .syncAppAppearance()
            }
            .onChange(of: showCompose) { _, open in
                if open { dismissSearchKeyboard() }
                if !open {
                    composeRecipient = nil
                    composeAnalyticsSource = "home_thank_someone"
                }
            }
            .onChange(of: searchFocused) { _, focused in
                searchActive = focused
            }
            .onChange(of: isSelected) { _, selected in
                if !selected { dismissSearchKeyboard() }
            }
            .onChange(of: path.count) { _, _ in
                // Pushing a profile (or any destination) should end search.
                dismissSearchKeyboard()
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

    private func listPaneWidth(for total: CGFloat) -> CGFloat {
        min(420, max(320, total * 0.4))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let gratitude = splitSelection?.wrappedValue {
            GratitudeDetailView(
                gratitude: gratitude,
                onOpenProfile: { path.append($0) }
            )
        } else {
            ContentUnavailableView(
                "Select an appreciation",
                systemImage: "heart",
                description: Text("Choose a note from Home to read it here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
    }

    private var feedChrome: some View {
        VStack(spacing: 0) {
            header
            HomeProfileSearch(
                focused: $searchFocused,
                onSelect: { profile in
                    Analytics.capture("home_search_profile_opened")
                    path.append(profile)
                },
                onInvite: { name in
                    Analytics.capture("home_search_invite_compose", ["query_length": name.count])
                    composeRecipient = name
                    composeAnalyticsSource = "home_search_invite"
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
                    .readableWidth()
            }
            content
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

            // Sidebar already has Thank someone — avoid a second CTA on iPad.
            if !usesSplitDetail {
                Button {
                    dismissSearchKeyboard()
                    composeRecipient = nil
                    composeAnalyticsSource = "home_thank_someone"
                    showCompose = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Thank Someone")
                            .font(Theme.body(13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color(hex: 0x2B1209))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Theme.ctaGradient, in: Capsule())
                    .shadow(color: Theme.coral.opacity(0.35), radius: 8, y: 2)
                }
                .accessibilityLabel("Thank Someone — share an appreciation")
            }
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
                                        presentPayItForward(from: accepted)
                                    },
                                    onDeclined: { id in
                                        resolvedPendingIds.insert(id)
                                        pendingToAccept.removeAll { $0.id == id }
                                        Task { await refreshWidgetSnapshot() }
                                    },
                                    onFailed: { gratitude in
                                        // Genuine network failure after optimistic remove —
                                        // allow retry with a fresh button state.
                                        resolvedPendingIds.remove(gratitude.id)
                                        pendingCardEpoch[gratitude.id, default: 0] += 1
                                        if !pendingToAccept.contains(where: { $0.id == gratitude.id }) {
                                            pendingToAccept.insert(gratitude, at: 0)
                                        }
                                        items.removeAll { $0.id == gratitude.id }
                                        Task { await refreshWidgetSnapshot() }
                                    }
                                )
                                .id("pending-\(item.id)-\(pendingCardEpoch[item.id, default: 0])")
                            }
                        }

                        ForEach(items) { item in
                            GratitudeCard(
                                gratitude: item,
                                isHearted: heartedIds.contains(item.id),
                                onHeart: { toggleHeart(item) },
                                onSelect: usesSplitDetail ? { selectPost(item) } : nil,
                                isSelected: splitSelection?.wrappedValue?.id == item.id,
                                onOpenProfile: { path.append($0) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .tabChromeBottomPadding()
                    .readableWidth()
                    .opacity(loading && !isEmpty ? 0.72 : 1)
                    .animation(.easeInOut(duration: 0.2), value: loading)
                }
                .scrollDismissesKeyboard(.immediately)
                .onChange(of: scrollToPendingToken) { _, _ in
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo("pendingThanks", anchor: .top)
                    }
                }
            }
        }
    }

    private func dismissSearchKeyboard() {
        if searchFocused { searchFocused = false }
        if searchActive { searchActive = false }
    }

    private func selectPost(_ item: Gratitude) {
        splitSelection?.wrappedValue = item
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

    private func presentPayItForward(from gratitude: Gratitude) {
        // Accept fires twice (optimistic + confirmed) — only nudge once per post.
        guard !payItForwardPresentedIds.contains(gratitude.id) else { return }
        payItForwardPresentedIds.insert(gratitude.id)
        let name = gratitude.author?.fullName
            ?? gratitude.author?.displayName
            ?? gratitude.author?.username
        // Slight delay so the pending card dismiss animation settles first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            payItForwardFromName = name ?? "someone"
            Analytics.capture("pay_it_forward_shown", ["source": "feed_accept"])
        }
    }

    private func applyPendingList(_ pending: [Gratitude]) {
        // Once accepted/declined this session, never resurrect — even if a stale
        // pending query still returns the row (or a failed twin request tries to).
        pendingToAccept = pending.filter { !resolvedPendingIds.contains($0.id) }
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
        Analytics.capture(wasHearted ? "appreciation_unhearted" : "appreciation_hearted", [
            "scope": scope.rawValue.lowercased(),
        ])
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
    /// When set (iPad split), opens the post in the detail column instead of pushing.
    var onSelect: (() -> Void)? = nil
    var isSelected: Bool = false
    /// Prefer programmatic profile open so avatars work inside multi-column shells.
    var onOpenProfile: ((Profile) -> Void)? = nil

    @State private var fullScreenImageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProfileAvatarLink(
                    profile: gratitude.author,
                    size: 38,
                    onOpen: onOpenProfile
                )
                openControl {
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
            }

            openControl {
                LinkifiedText(
                    text: gratitude.message,
                    font: Theme.body(15),
                    foreground: Theme.textPrimary.opacity(0.92)
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let url = gratitude.mediaURL {
                let isVideo = gratitude.mediaType?.lowercased().hasPrefix("video") == true
                if isVideo {
                    FlexiblePostMedia(url: url, mediaType: gratitude.mediaType, maxHeight: 420)
                } else {
                    Button { fullScreenImageURL = url } label: {
                        FlexiblePostImage(url: url, maxHeight: 420)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                Button(action: onHeart) {
                    HStack(spacing: 5) {
                        Image(systemName: isHearted ? "heart.fill" : "heart")
                            .foregroundStyle(isHearted ? Theme.coral : Theme.textSecondary)
                        Text("\(gratitude.heartCount)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.body(14, weight: .medium))
                }
                .accessibilityLabel(isHearted ? "Remove heart" : "Heart")

                HeartedByView(gratitudeId: gratitude.id, heartCount: gratitude.heartCount)

                Spacer(minLength: 0)
                if gratitude.visibility == .private {
                    Label("Private", systemImage: "lock.fill")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(16)
        .card()
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.coral.opacity(0.85), lineWidth: 2)
            }
        }
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
    }

    @ViewBuilder
    private func openControl<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onSelect {
            Button(action: onSelect, label: content)
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: gratitude, label: content)
                .buttonStyle(.plain)
        }
    }
}

struct AvatarView: View {
    let profile: Profile?
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = profile?.avatarURL {
                CachedAsyncImage(url: url, maxPixelSize: RemoteImageCache.avatarMaxPixelSize) { image in
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
    var focused: FocusState<Bool>.Binding
    var onSelect: (Profile) -> Void
    var onInvite: (String) -> Void

    @State private var query = ""
    @State private var results: [Profile] = []
    @State private var searching = false
    @State private var didSearch = false

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showResults: Bool {
        focused.wrappedValue && trimmed.count >= 2
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
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(focused.wrappedValue ? Theme.coral : Theme.textTertiary)

                TextField("Search people by name", text: $query)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(focused)
                    .submitLabel(.search)

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        searching = false
                        didSearch = false
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
                    .strokeBorder(focused.wrappedValue ? Theme.coral.opacity(0.45) : Theme.hairline, lineWidth: 1)
            )

            // Native search-bar Cancel — ends editing and restores the tab bar.
            if focused.wrappedValue {
                Button("Cancel") {
                    clear()
                }
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.coral)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: focused.wrappedValue)
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
                        focused.wrappedValue = false
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
                        focused.wrappedValue = false
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
        focused.wrappedValue = false
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
