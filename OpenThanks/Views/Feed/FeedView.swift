import SwiftUI
import UIKit

struct FeedView: View {
    enum Scope: String, CaseIterable {
        case personal = "Personal"
        case world = "World"

        var title: String {
            switch self {
            case .personal: "My Feed"
            case .world: "World Feed"
            }
        }
    }

    @Binding var path: NavigationPath
    /// False when another tab is showing — Home stays mounted, so clear search focus.
    var isSelected: Bool = true
    /// Mirrors search focus so the tab bar can hide during search (native search-mode).
    @Binding var searchActive: Bool
    /// When set (iPad sidebar shell), card taps can fill a detail column instead of pushing.
    /// Side-by-side detail is landscape-only — portrait keeps a full-width feed.
    var splitSelection: Binding<Gratitude?>? = nil
    @Environment(AuthService.self) private var auth
    @Environment(UserBlockService.self) private var userBlocks
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage("hasSeenFirstSendTip") private var hasSeenFirstSendTip = false
    @State private var updateChecker = AppUpdateChecker.shared
    @State private var calendarReminder = CalendarConnectReminder.shared
    @State private var campaign = CampaignService.shared
    @State private var showCalendarConnect = false
    @State private var scope: Scope = .personal
    /// Per-scope lists so My ↔ World can page without flashing the wrong feed.
    @State private var personalItems: [Gratitude] = []
    @State private var worldItems: [Gratitude] = []
    @State private var personalHeartedIds: Set<UUID> = []
    @State private var worldHeartedIds: Set<UUID> = []
    @State private var personalLoading = true
    @State private var worldLoading = false
    @State private var personalError: String?
    @State private var worldError: String?
    @State private var personalLoadedOnce = false
    @State private var worldLoadedOnce = false
    @State private var personalHasMore = false
    @State private var worldHasMore = false
    @State private var personalLoadingMore = false
    @State private var worldLoadingMore = false
    @State private var pendingToAccept: [Gratitude] = []
    /// Ids the user already accepted/declined this session — keeps pull-to-refresh
    /// from resurrecting a card when a stale pending query races the accept write.
    @State private var resolvedPendingIds: Set<UUID> = []
    /// Bumped when a failed accept re-inserts a card so SwiftUI doesn't reuse
    /// stuck "Accepting…" @State from the previous attempt.
    @State private var pendingCardEpoch: [UUID: Int] = [:]
    @State private var pendingSentCount = 0
    @State private var showCompose = false
    @State private var composeRecipient: String?
    @State private var composeAnalyticsSource = "home_thank_someone"
    /// After accepting, gently invite the recipient to thank someone else.
    @State private var payItForwardFromName: String?
    @State private var payItForwardParentId: UUID?
    @State private var payItForwardPresentedIds: Set<UUID> = []
    /// Set before the sheet dismisses on "Thank someone", so that dismiss is not a dismissal.
    @State private var payItForwardDidThank = false
    @State private var composeInspiredById: UUID?
    @State private var composeInspiredByName: String?
    /// Once per session: if Personal has nothing, land on World instead.
    @State private var didAutoSwitchToWorld = false
    /// Bumped when auto-switching so the page `TabView` resyncs (iPad often
    /// ignores a programmatic selection change without recreating the pager).
    @State private var feedPagerEpoch = 0
    /// Suppresses the scope-change haptic for the automatic empty→World handoff.
    @State private var suppressNextScopeHaptic = false
    @State private var scrollToPendingToken = 0
    @State private var personalLoadGeneration = 0
    @State private var worldLoadGeneration = 0
    @Namespace private var scopePickerNamespace
    @FocusState private var searchFocused: Bool
    /// Collapses when scrolling down the feed; reveals on scroll up (Messages/Safari-style).
    @State private var searchBarVisible = true
    @State private var lastScrollOffset: CGFloat = 0
    /// Skip direction changes caused by the bar itself collapsing/expanding.
    @State private var ignoreScrollUntil: Date = .distantPast
    /// Non-empty query keeps the bar visible even while scrolling.
    @State private var searchHasQuery = false

    private var items: [Gratitude] { items(for: scope) }
    private var heartedIds: Set<UUID> { hearts(for: scope) }
    private var loading: Bool { isLoading(for: scope) }
    private var error: String? { loadError(for: scope) }
    private var isEmpty: Bool {
        items.isEmpty && (scope == .personal ? pendingToAccept.isEmpty : true)
    }

    private func items(for scope: Scope) -> [Gratitude] {
        scope == .personal ? personalItems : worldItems
    }
    private func hearts(for scope: Scope) -> Set<UUID> {
        scope == .personal ? personalHeartedIds : worldHeartedIds
    }
    private func isLoading(for scope: Scope) -> Bool {
        scope == .personal ? personalLoading : worldLoading
    }
    private func loadError(for scope: Scope) -> String? {
        scope == .personal ? personalError : worldError
    }
    private func setItems(_ value: [Gratitude], for scope: Scope) {
        if scope == .personal { personalItems = value } else { worldItems = value }
    }
    private func setHearts(_ value: Set<UUID>, for scope: Scope) {
        if scope == .personal { personalHeartedIds = value } else { worldHeartedIds = value }
    }
    private func setLoading(_ value: Bool, for scope: Scope) {
        if scope == .personal { personalLoading = value } else { worldLoading = value }
    }
    private func setError(_ value: String?, for scope: Scope) {
        if scope == .personal { personalError = value } else { worldError = value }
    }
    private func mutateItems(for scope: Scope, _ body: (inout [Gratitude]) -> Void) {
        var copy = items(for: scope)
        body(&copy)
        setItems(copy, for: scope)
    }
    private func mutateHearts(for scope: Scope, _ body: (inout Set<UUID>) -> Void) {
        var copy = hearts(for: scope)
        body(&copy)
        setHearts(copy, for: scope)
    }
    private var isSearchChromeVisible: Bool { searchBarVisible || searchFocused || searchHasQuery }
    private var shouldKeepSearchVisible: Bool { searchFocused || searchHasQuery }
    /// Soft update nudge — skip while first-send tip / compose / pay-it-forward are up.
    private var shouldShowUpdateBanner: Bool {
        updateChecker.shouldShowBanner
            && hasSeenFirstSendTip
            && !showCompose
            && payItForwardFromName == nil
            && isSelected
    }
    /// Soft calendar reconnect — same quiet conditions as the update banner.
    private var shouldShowCalendarBanner: Bool {
        calendarReminder.shouldShowBanner
            && hasSeenFirstSendTip
            && !showCompose
            && !showCalendarConnect
            && payItForwardFromName == nil
            && isSelected
    }
    /// iPad sidebar shell (portrait or landscape) — hides the duplicate Thank Someone CTA.
    private var isSplitShell: Bool { splitSelection != nil }
    /// List + detail columns: only when the shell is active and we're in landscape
    /// (`verticalSizeClass == .compact` on iPad). Portrait stays sidebar + full feed.
    private var usesSplitDetail: Bool {
        isSplitShell && verticalSizeClass == .compact
    }
    private var showPayItForward: Binding<Bool> {
        Binding(
            get: { payItForwardFromName != nil },
            set: { presented in
                if !presented { dismissPayItForwardSheet() }
            }
        )
    }

    /// User closed the sheet (Not now, close, or swipe). Thank-someone sets
    /// `payItForwardDidThank` first so it is not counted here.
    private func dismissPayItForwardSheet() {
        let parentId = payItForwardParentId
        let wasShowing = payItForwardFromName != nil
        if wasShowing, !payItForwardDidThank, let parentId {
            Analytics.payItForwardDismissed(
                parentGratitudeId: parentId,
                surface: "feed",
                source: "feed_accept"
            )
        }
        payItForwardDidThank = false
        payItForwardFromName = nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            feedRoot
                .syncAppAppearance()
        }
    }

    /// Split out of `body` so SwiftUI type-checking stays tractable.
    @ViewBuilder
    private var feedRoot: some View {
        feedChromeOrSplit
            .background(Theme.background)
            // Only while searching — otherwise this fights scroll-direction hide/show.
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    guard searchFocused else { return }
                    dismissSearchKeyboard()
                }
            )
            .task(id: scope) {
                let loadedOnce = scope == .personal ? personalLoadedOnce : worldLoadedOnce
                if !loadedOnce {
                    await load(for: scope)
                }
            }
            // Keep the bar hidden on the Home root; show it when a profile/post is pushed
            // so Back works (especially important on iPad two-pane).
            .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .appDestinations()
            .environment(\.openProfile) { path.append($0) }
            .composeCover(isPresented: $showCompose) {
                ComposeView(
                    initialRecipient: composeRecipient,
                    inspiredByGratitudeId: composeInspiredById,
                    inspiredByAuthorName: composeInspiredByName,
                    analyticsSource: composeAnalyticsSource
                )
            }
            .sheet(isPresented: showPayItForward) {
                PayItForwardSheet(
                    fromName: payItForwardFromName,
                    parentGratitudeId: payItForwardParentId,
                    analyticsSurface: "feed",
                    analyticsSource: "feed_accept",
                    onThankSomeone: {
                        payItForwardDidThank = true
                        composeRecipient = nil
                        composeInspiredById = payItForwardParentId
                        composeInspiredByName = payItForwardFromName
                        composeAnalyticsSource = "post_accept_pay_it_forward"
                        if let parentId = payItForwardParentId {
                            Analytics.payItForwardTapped(
                                parentGratitudeId: parentId,
                                surface: "feed",
                                source: "feed_accept"
                            )
                        }
                        showCompose = true
                    }
                )
                .syncAppAppearance()
            }
            .onChange(of: searchFocused) { _, focused in
                searchActive = focused
                if focused { searchBarVisible = true }
            }
            .onChange(of: isEmpty) { _, empty in
                if empty { searchBarVisible = true }
            }
            .onChange(of: pendingToAccept.count) { _, count in
                NotificationCenter.default.post(
                    name: .homePendingAcceptCount,
                    object: nil,
                    userInfo: ["count": count]
                )
            }
            .onChange(of: showCompose) { _, open in
                if open { dismissSearchKeyboard() }
                if !open {
                    composeRecipient = nil
                    composeInspiredById = nil
                    composeInspiredByName = nil
                    composeAnalyticsSource = "home_thank_someone"
                }
            }
            .onChange(of: isSelected) { _, selected in
                if !selected {
                    dismissSearchKeyboard()
                } else {
                    Task { await refreshPendingAccept(reason: "home_selected") }
                }
            }
            .onChange(of: usesSplitDetail) { _, enabled in
                // Rotating to portrait: show the open post as a push, free the feed width.
                guard !enabled, let gratitude = splitSelection?.wrappedValue else { return }
                splitSelection?.wrappedValue = nil
                path.append(gratitude)
            }
            .onChange(of: path.count) { _, _ in
                dismissSearchKeyboard()
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusReceivedThanks)) { _ in
                handleFocusReceivedThanks()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pendingThanksShouldRefresh)) { _ in
                Task { await refreshPendingAccept(reason: "push_or_signal") }
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissTransientSheets)) { _ in
                payItForwardFromName = nil
                payItForwardParentId = nil
            }
            .onReceive(NotificationCenter.default.publisher(for: .gratitudeAccepted)) { note in
                guard let gratitude = note.object as? Gratitude else { return }
                applyAcceptedPending(gratitude)
            }
            .onReceive(NotificationCenter.default.publisher(for: .gratitudeCreated)) { note in
                guard let gratitude = note.object as? Gratitude else { return }
                applyCreated(gratitude)
                campaign.noteSent(at: gratitude.createdAt ?? Date())
            }
            .onReceive(NotificationCenter.default.publisher(for: .profileDidUpdate)) { note in
                guard let updated = note.object as? Profile else { return }
                applyProfileUpdate(updated)
            }
            .onReceive(NotificationCenter.default.publisher(for: .userDidBlock)) { note in
                guard let blockedId = note.object as? UUID else { return }
                handleUserDidBlock(blockedId)
            }
    }

    @ViewBuilder
    private var feedChromeOrSplit: some View {
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

    private func handleFocusReceivedThanks() {
        if scope != .personal {
            suppressNextScopeHaptic = true
            withAnimation(Self.scopeSwitchAnimation) {
                scope = .personal
            }
        }
        Task {
            await refreshPendingAccept(reason: "focus_received")
            // Let My Feed appear before scrolling to the pending header.
            try? await Task.sleep(for: .milliseconds(120))
            scrollToPendingToken += 1
        }
    }

    private func handleUserDidBlock(_ blockedId: UUID) {
        setItems(userBlocks.filterGratitudes(personalItems), for: .personal)
        setItems(userBlocks.filterGratitudes(worldItems), for: .world)
        pendingToAccept = userBlocks.filterGratitudes(pendingToAccept)
        let selected = splitSelection?.wrappedValue
        if selected?.authorId == blockedId || selected?.recipientId == blockedId {
            splitSelection?.wrappedValue = nil
        }
    }

    private func listPaneWidth(for total: CGFloat) -> CGFloat {
        min(420, max(320, total * 0.4))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let gratitude = splitSelection?.wrappedValue {
            GratitudeRouteView(
                gratitude: gratitude,
                onOpenProfile: { path.append($0) }
            )
        } else {
            SplitDetailPlaceholder(
                title: "Select an appreciation",
                systemImage: "heart.fill",
                message: "Choose a note from Home to read it here."
            )
        }
    }

    private var feedChrome: some View {
        VStack(spacing: 0) {
            header
            if shouldShowUpdateBanner {
                AppUpdateBanner(
                    storeVersion: updateChecker.storeVersion,
                    onUpdate: { updateChecker.openAppStore() },
                    onLater: { updateChecker.snooze() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)
                .readableWidth()
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear { updateChecker.trackBannerShown() }
            }
            if shouldShowCalendarBanner {
                CalendarConnectBanner(
                    onConnect: {
                        calendarReminder.trackConnectTapped()
                        showCalendarConnect = true
                    },
                    onLater: { calendarReminder.snooze() }
                )
                .padding(.horizontal, 16)
                .padding(.top, shouldShowUpdateBanner ? 4 : 10)
                .padding(.bottom, 4)
                .readableWidth()
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear { calendarReminder.trackBannerShown() }
            }
            if pendingSentCount > 0 {
                PendingAppreciationsBanner(count: pendingSentCount)
                    .padding(.horizontal, 16)
                    .padding(.top, (shouldShowUpdateBanner || shouldShowCalendarBanner) ? 4 : 10)
                    .padding(.bottom, 4)
                    .readableWidth()
            }
            if let prompt = campaign.todayPrompt {
                CampaignPromptCard(
                    day: prompt.day,
                    theme: prompt.theme,
                    prompt: prompt.prompt,
                    daysSent: campaign.daysSent,
                    totalDays: campaign.progressTotal,
                    onThank: { thankFromCampaign(prompt) }
                )
                .padding(.horizontal, 16)
                .padding(.top, (shouldShowUpdateBanner || shouldShowCalendarBanner || pendingSentCount > 0) ? 4 : 10)
                .padding(.bottom, 4)
                .readableWidth()
                .task(id: prompt.day) {
                    guard let id = campaign.feed?.id else { return }
                    Analytics.campaignPromptShown(campaign: id, day: prompt.day)
                    if let userId = auth.userId {
                        await campaign.refreshProgress(authorId: userId)
                    }
                }
            }
            HomeProfileSearch(
                focused: $searchFocused,
                onQueryChange: { hasQuery in
                    searchHasQuery = hasQuery
                    if hasQuery { searchBarVisible = true }
                },
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
            .padding(.top, isSearchChromeVisible ? (hasTopHomeBanner ? 6 : 10) : 0)
            .padding(.bottom, isSearchChromeVisible ? 2 : 0)
            .frame(maxHeight: isSearchChromeVisible ? nil : 0, alignment: .top)
            .opacity(isSearchChromeVisible ? 1 : 0)
            .clipped()
            .allowsHitTesting(isSearchChromeVisible)
            // No spring here — animating height fights UIScrollView offset tracking.
            .animation(.easeInOut(duration: 0.18), value: isSearchChromeVisible)
            .zIndex(2)

            picker
            // Page swipe between My Feed and World Feed (picker stays in sync).
            TabView(selection: $scope) {
                scopePage(for: .personal)
                    .tag(Scope.personal)
                scopePage(for: .world)
                    .tag(Scope.world)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .id(feedPagerEpoch)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: shouldShowUpdateBanner)
        .animation(.easeInOut(duration: 0.2), value: shouldShowCalendarBanner)
        .onAppear { calendarReminder.refresh() }
        .task { await campaign.refresh() }
        .onChange(of: isSelected) { _, selected in
            if selected { calendarReminder.refresh() }
        }
        .sheet(isPresented: $showCalendarConnect, onDismiss: {
            calendarReminder.refresh()
        }) {
            // 5.1.1(iv): no Close / swipe-dismiss that skips the Calendar
            // permission request after this custom rationale.
            NavigationStack {
                CalendarPermissionView(
                    onFinished: {
                        showCalendarConnect = false
                        calendarReminder.refresh()
                    },
                    analyticsSource: "home_banner"
                )
            }
            .syncAppAppearance()
            .presentationDetents([.large])
            .interactiveDismissDisabled()
        }
        .onChange(of: scope) { _, next in
            dismissSearchKeyboard()
            searchBarVisible = true
            lastScrollOffset = 0
            if suppressNextScopeHaptic {
                suppressNextScopeHaptic = false
            } else {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Analytics.capture("home_feed_scope_changed", [
                    "scope": next == .personal ? "personal" : "world",
                ])
            }
            // Prefetch the other scope once (generation-guarded; no-ops if already loaded).
            Task { await prefetchOpposite(of: next) }
        }
    }

    private var hasTopHomeBanner: Bool {
        shouldShowUpdateBanner || shouldShowCalendarBanner || pendingSentCount > 0 || campaign.todayPrompt != nil
    }

    private func thankFromCampaign(_ prompt: CampaignPrompt) {
        dismissSearchKeyboard()
        if let id = campaign.feed?.id {
            Analytics.campaignPromptTapped(campaign: id, day: prompt.day)
        }
        campaign.openCompose(prompt: prompt, analyticsSource: "campaign_home")
    }

    @ViewBuilder
    private func scopePage(for page: Scope) -> some View {
        feedContent(for: page)
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
            if !isSplitShell {
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
                Button {
                    selectScope(s)
                } label: {
                    Text(s.title)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(scope == s ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background {
                            if scope == s {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Theme.surfaceRaised)
                                    .matchedGeometryEffect(id: "feedScopePill", in: scopePickerNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == s ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .animation(Self.scopeSwitchAnimation, value: scope)
    }

    private static let scopeSwitchAnimation = Animation.spring(response: 0.42, dampingFraction: 0.86)

    private func selectScope(_ next: Scope) {
        guard next != scope else { return }
        dismissSearchKeyboard()
        withAnimation(Self.scopeSwitchAnimation) {
            scope = next
            searchBarVisible = true
            lastScrollOffset = 0
        }
    }

    @ViewBuilder
    private func feedContent(for page: Scope) -> some View {
        let pageItems = items(for: page)
        let pageHearts = hearts(for: page)
        let pageLoading = isLoading(for: page)
        let pageError = loadError(for: page)
        let pageEmpty = pageItems.isEmpty && (page == .personal ? pendingToAccept.isEmpty : true)

        if pageLoading && pageEmpty {
            VStack {
                Spacer()
                ProgressView().tint(Theme.coral)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let pageError, pageEmpty {
            VStack {
                Spacer()
                VStack(spacing: 8) {
                    Text("Couldn't load Home").font(Theme.body(16, weight: .semibold))
                    Text(pageError).font(Theme.body(13)).foregroundStyle(Theme.textSecondary)
                    Button("Try again") { Task { await load(for: page) } }
                        .foregroundStyle(Theme.coral)
                }
                .padding(24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pageEmpty {
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    HeartMark(size: 48)
                    Text(page == .personal
                         ? "My Feed shows people you’ve thanked, who’ve thanked you, or whose posts you’ve hearted. Send your first one to get started."
                         : "Nothing public yet — be the first.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    if page == .personal {
                        Button {
                            Analytics.capture("home_empty_first_send_tapped")
                            ComposeLaunchBridge.shared.queue(analyticsSource: "home_empty_first_send")
                        } label: {
                            Text("Send your first appreciation")
                                .font(Theme.body(15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.ctaGradient, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 40)
                        .accessibilityLabel("Send your first appreciation")
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if page == .personal, !pendingToAccept.isEmpty {
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
                                        mutateItems(for: .personal) { $0.removeAll { $0.id == gratitude.id } }
                                        Task { await refreshWidgetSnapshot() }
                                    }
                                )
                                .id("pending-\(item.id)-\(pendingCardEpoch[item.id, default: 0])")
                            }
                        }

                        ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                            GratitudeCard(
                                gratitude: item,
                                isHearted: pageHearts.contains(item.id),
                                onHeart: { toggleHeart(item, in: page) },
                                onSelect: usesSplitDetail ? { selectPost(item) } : nil,
                                isSelected: splitSelection?.wrappedValue?.id == item.id,
                                onOpenProfile: { path.append($0) }
                            )
                            .onAppear {
                                if index >= pageItems.count - 3 {
                                    Task { await loadMore(for: page) }
                                }
                            }
                        }

                        if (page == .personal ? personalLoadingMore : worldLoadingMore) {
                            ProgressView()
                                .tint(Theme.coral)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .tabChromeBottomPadding()
                    .readableWidth()
                    .opacity(pageLoading && !pageEmpty ? 0.78 : 1)
                    .animation(.easeInOut(duration: 0.28), value: pageLoading)
                    // UIScrollView KVO — PreferenceKey on LazyVStack often never moves on iOS 17.
                    .background {
                        FeedScrollOffsetReader { offset in
                            guard page == scope else { return }
                            handleFeedScroll(to: offset)
                        }
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .refreshable { await load(for: page) }
                .onChange(of: scrollToPendingToken) { _, _ in
                    guard page == .personal else { return }
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

    /// Hide search while scrolling down; reveal on scroll up or at the top.
    private func handleFeedScroll(to newOffset: CGFloat) {
        // Empty / loading states don't use this ScrollView — still keep bar up if active.
        if shouldKeepSearchVisible {
            if !searchBarVisible { searchBarVisible = true }
            lastScrollOffset = newOffset
            return
        }

        // Near the top — always show.
        if newOffset <= 12 {
            setSearchBarVisible(true, trackingOffset: newOffset)
            return
        }

        // Collapsing the chrome resizes the ScrollView and can fake a direction change.
        if Date() < ignoreScrollUntil {
            lastScrollOffset = newOffset
            return
        }

        let delta = newOffset - lastScrollOffset
        // Ignore tiny jitter / rubber-band.
        guard abs(delta) >= 8 else { return }
        lastScrollOffset = newOffset

        if delta > 0 {
            // Scrolling down (content moves up) — tuck search away.
            setSearchBarVisible(false, trackingOffset: newOffset)
        } else {
            // Scrolling up — bring it back.
            setSearchBarVisible(true, trackingOffset: newOffset)
        }
    }

    private func setSearchBarVisible(_ visible: Bool, trackingOffset: CGFloat) {
        lastScrollOffset = trackingOffset
        guard searchBarVisible != visible else { return }
        searchBarVisible = visible
        ignoreScrollUntil = Date().addingTimeInterval(0.28)
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
        guard gratitude.status == .accepted else {
            Task { await refreshWidgetSnapshot() }
            return
        }

        // My Feed: anything you sent or received.
        upsertAccepted(gratitude, into: .personal)

        // World Feed: public accepts only (matches worldFeed query).
        if gratitude.senderMarkedPublic {
            upsertAccepted(gratitude, into: .world)
        }

        Task { await refreshWidgetSnapshot() }
    }

    private func upsertAccepted(_ gratitude: Gratitude, into scope: Scope) {
        mutateItems(for: scope) { list in
            if let idx = list.firstIndex(where: { $0.id == gratitude.id }) {
                list[idx] = gratitude
            } else {
                list.insert(gratitude, at: 0)
            }
            list.sort { $0.acceptanceSortDate > $1.acceptanceSortDate }
        }
    }

    /// After compose: bump pending-sent chrome; if somehow already accepted, insert into feeds.
    private func applyCreated(_ gratitude: Gratitude) {
        guard let userId = auth.userId, gratitude.authorId == userId else { return }
        if gratitude.status == .accepted {
            upsertAccepted(gratitude, into: .personal)
            if gratitude.senderMarkedPublic {
                upsertAccepted(gratitude, into: .world)
            }
        } else {
            pendingSentCount += 1
        }
    }

    private func applyProfileUpdate(_ updated: Profile) {
        for scope in Scope.allCases {
            mutateItems(for: scope) { list in
                for i in list.indices {
                    if list[i].authorId == updated.id { list[i].author = updated }
                    if list[i].recipientId == updated.id { list[i].recipient = updated }
                }
            }
        }
        for i in pendingToAccept.indices {
            if pendingToAccept[i].authorId == updated.id { pendingToAccept[i].author = updated }
            if pendingToAccept[i].recipientId == updated.id { pendingToAccept[i].recipient = updated }
        }
    }

    private func presentPayItForward(from gratitude: Gratitude) {
        // Accept fires twice (optimistic + confirmed) — only nudge once per post.
        guard !payItForwardPresentedIds.contains(gratitude.id) else { return }
        payItForwardPresentedIds.insert(gratitude.id)
        payItForwardDidThank = false
        Analytics.payItForwardOffered(
            parentGratitudeId: gratitude.id,
            surface: "feed",
            source: "feed_accept"
        )
        let name = gratitude.author?.fullName
            ?? gratitude.author?.displayName
            ?? gratitude.author?.username
        // Slight delay so the pending card dismiss animation settles first.
        // The impression fires from the card's onAppear, not from this delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            payItForwardParentId = gratitude.id
            payItForwardFromName = name ?? "someone"
        }
    }

    private func applyPendingList(_ pending: [Gratitude]) {
        // Once accepted/declined this session, never resurrect — even if a stale
        // pending query still returns the row (or a failed twin request tries to).
        pendingToAccept = pending.filter { !resolvedPendingIds.contains($0.id) }
    }

    /// Soft-fail pending load — never blank the accepted feed on a pending error.
    private func loadPendingAcceptBundle(userId: UUID) async -> (pending: [Gratitude], pendingSent: Int) {
        do {
            async let pendingTask = GratitudeService.pendingToAccept(
                userId: userId,
                email: auth.currentProfile?.email,
                phone: auth.currentProfile?.phone
            )
            async let pendingSentTask = GratitudeService.pendingCount(authorId: userId)
            let pending = userBlocks.filterGratitudes(try await pendingTask)
            let pendingSent = try await pendingSentTask
            return (pending, pendingSent)
        } catch {
            if !error.isCancellation {
                Analytics.capture("home_pending_load_failed", [
                    "message": String(error.localizedDescription.prefix(120)),
                ])
            }
            return (pendingToAccept, pendingSentCount)
        }
    }

    /// Lightweight pending refresh (Home selected, push, focusReceived) without reloading the feed.
    private func refreshPendingAccept(reason: String) async {
        guard let userId = auth.userId else { return }
        let bundle = await loadPendingAcceptBundle(userId: userId)
        for item in bundle.pending where !resolvedPendingIds.contains(item.id) {
            await GratitudeService.ensurePendingRecipientLinked(item, userId: userId)
        }
        applyPendingList(bundle.pending)
        pendingSentCount = bundle.pendingSent
        await refreshWidgetSnapshot()
        Analytics.capture("home_pending_refreshed", [
            "reason": reason,
            "pending_count": bundle.pending.count,
        ])
    }

    private func prefetchOpposite(of current: Scope) async {
        let other: Scope = current == .personal ? .world : .personal
        let alreadyLoaded = other == .personal ? personalLoadedOnce : worldLoadedOnce
        guard !alreadyLoaded else { return }
        await load(for: other)
    }

    private func nextLoadGeneration(for target: Scope) -> Int {
        if target == .personal {
            personalLoadGeneration += 1
            return personalLoadGeneration
        }
        worldLoadGeneration += 1
        return worldLoadGeneration
    }

    private func currentLoadGeneration(for target: Scope) -> Int {
        target == .personal ? personalLoadGeneration : worldLoadGeneration
    }

    private func load(for target: Scope) async {
        guard let userId = auth.userId else { return }
        let generation = nextLoadGeneration(for: target)
        setLoading(true, for: target)
        setError(nil, for: target)
        do {
            async let feedTask = target == .personal
                ? GratitudeService.personalFeed(userId: userId)
                : GratitudeService.worldFeed()

            // World refresh still reloads pending-to-accept so receive isn’t Personal-only.
            let pageResult = try await feedTask
            let result = userBlocks.filterGratitudes(pageResult.items)
            let pendingBundle = await loadPendingAcceptBundle(userId: userId)
            let pending = pendingBundle.pending
            let pendingSent = pendingBundle.pendingSent

            guard generation == currentLoadGeneration(for: target) else { return }

            // Attach recipient + pending notification as soon as we see them —
            // don't wait until accept/decline (which used to create the notice).
            for item in pending where !resolvedPendingIds.contains(item.id) {
                await GratitudeService.ensurePendingRecipientLinked(item, userId: userId)
            }

            guard generation == currentLoadGeneration(for: target) else { return }

            // Empty personal feed → show World so Home isn't a blank screen
            // (especially on iPad, where the page TabView can ignore a bare
            // selection flip). Keep My Feed when there are pending accepts —
            // those only render on Personal.
            if target == .personal, result.isEmpty, pending.isEmpty, !didAutoSwitchToWorld {
                didAutoSwitchToWorld = true
                applyPendingList(pending)
                pendingSentCount = pendingSent
                setItems([], for: .personal)
                setHearts([], for: .personal)
                personalHasMore = false
                personalLoadedOnce = true
                setLoading(false, for: .personal)
                await refreshWidgetSnapshot()
                suppressNextScopeHaptic = true
                feedPagerEpoch += 1
                withAnimation(Self.scopeSwitchAnimation) {
                    scope = .world
                }
                // Load World here so the rebuilt pager isn't stuck on an empty page
                // waiting for `.task(id: scope)` (unreliable after the id bump on iPad).
                await load(for: .world)
                return
            }

            async let heartsTask = GratitudeService.myHearts(userId: userId, among: result.map(\.id))
            let hearts = (try? await heartsTask) ?? hearts(for: target)

            guard generation == currentLoadGeneration(for: target) else { return }

            withAnimation(.easeInOut(duration: 0.28)) {
                setItems(result, for: target)
                setHearts(hearts, for: target)
                if target == .personal {
                    personalHasMore = pageResult.hasMore
                    personalLoadedOnce = true
                } else {
                    worldHasMore = pageResult.hasMore
                    worldLoadedOnce = true
                }
                applyPendingList(pending)
                pendingSentCount = pendingSent
            }
            await refreshWidgetSnapshot()
        } catch {
            if !error.isCancellation {
                setError(error.localizedDescription, for: target)
            }
        }
        if generation == currentLoadGeneration(for: target) {
            withAnimation(.easeInOut(duration: 0.28)) {
                setLoading(false, for: target)
            }
        }
    }

    /// Append older feed items when the user scrolls near the end of the list.
    private func loadMore(for target: Scope) async {
        guard let userId = auth.userId else { return }
        let hasMore = target == .personal ? personalHasMore : worldHasMore
        let loadingMore = target == .personal ? personalLoadingMore : worldLoadingMore
        guard hasMore, !loadingMore, !isLoading(for: target) else { return }
        let current = items(for: target)
        guard let before = current.last?.acceptedAt ?? current.last?.createdAt else { return }

        if target == .personal { personalLoadingMore = true } else { worldLoadingMore = true }
        defer {
            if target == .personal { personalLoadingMore = false } else { worldLoadingMore = false }
        }

        do {
            let pageResult = try await (
                target == .personal
                    ? GratitudeService.personalFeed(userId: userId, before: before)
                    : GratitudeService.worldFeed(before: before)
            )
            let fresh = userBlocks.filterGratitudes(pageResult.items)
            var existing = Set(current.map(\.id))
            let appended = fresh.filter { existing.insert($0.id).inserted }
            guard !appended.isEmpty || !pageResult.hasMore else {
                // Cursor didn't advance — stop to avoid a tight loop.
                if target == .personal { personalHasMore = false } else { worldHasMore = false }
                return
            }
            let newHearts = (try? await GratitudeService.myHearts(
                userId: userId,
                among: appended.map(\.id)
            )) ?? []
            mutateItems(for: target) { $0.append(contentsOf: appended) }
            mutateHearts(for: target) { $0.formUnion(newHearts) }
            if target == .personal {
                personalHasMore = pageResult.hasMore
            } else {
                worldHasMore = pageResult.hasMore
            }
        } catch {
            if !error.isCancellation {
                // Soft-fail: keep current list; user can pull to refresh.
            }
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

    private func toggleHeart(_ item: Gratitude, in page: Scope) {
        guard let userId = auth.userId else { return }
        let wasHearted = hearts(for: page).contains(item.id)
        // Optimistic update
        mutateHearts(for: page) { set in
            if wasHearted { set.remove(item.id) } else { set.insert(item.id) }
        }
        Analytics.capture(wasHearted ? "appreciation_unhearted" : "appreciation_hearted", [
            "scope": page.rawValue.lowercased(),
        ])
        let delta = wasHearted ? -1 : 1
        mutateItems(for: page) { list in
            if let idx = list.firstIndex(where: { $0.id == item.id }) {
                list[idx].hearts = [CountHolder(count: max(0, item.heartCount + delta))]
            }
        }
        // Keep the other scope's card in sync only when the same post is cached there.
        let other: Scope = page == .personal ? .world : .personal
        if items(for: other).contains(where: { $0.id == item.id }) {
            mutateItems(for: other) { list in
                if let idx = list.firstIndex(where: { $0.id == item.id }) {
                    list[idx].hearts = [CountHolder(count: max(0, list[idx].heartCount + delta))]
                }
            }
            mutateHearts(for: other) { set in
                if wasHearted { set.remove(item.id) } else { set.insert(item.id) }
            }
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
                mutateHearts(for: page) { set in
                    if wasHearted { set.insert(item.id) } else { set.remove(item.id) }
                }
                mutateItems(for: page) { list in
                    if let idx = list.firstIndex(where: { $0.id == item.id }) {
                        list[idx].hearts = [CountHolder(count: max(0, item.heartCount))]
                    }
                }
                if items(for: other).contains(where: { $0.id == item.id }) {
                    mutateHearts(for: other) { set in
                        if wasHearted { set.insert(item.id) } else { set.remove(item.id) }
                    }
                    mutateItems(for: other) { list in
                        if let idx = list.firstIndex(where: { $0.id == item.id }) {
                            list[idx].hearts = [CountHolder(count: max(0, item.heartCount))]
                        }
                    }
                }
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
    @Environment(AuthService.self) private var auth

    @State private var fullScreenImageURL: URL?
    @State private var preparingShare = false
    @State private var systemSharePayload: SystemSharePayload?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProfileAvatarLink(
                    profile: gratitude.author,
                    size: 38,
                    onOpen: onOpenProfile
                )
                VStack(alignment: .leading, spacing: 2) {
                    // Single flowing sentence so long names wrap naturally.
                    // Profile names are links; “thanked” / unknown recipient open the post.
                    openControl {
                        Text(thankedHeadline)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .tint(Theme.textPrimary)
                    }
                    .environment(\.openURL, OpenURLAction(handler: handleThankedHeadlineURL))

                    openControl {
                        Group {
                            if let date = gratitude.displayDate {
                                Text(date, format: .relative(presentation: .named))
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
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

                HeartedByView(
                    gratitudeId: gratitude.id,
                    heartCount: gratitude.heartCount,
                    onOpenProfile: onOpenProfile
                )

                Spacer(minLength: 0)

                Button {
                    Task { await presentSystemShare() }
                } label: {
                    Group {
                        if preparingShare && systemSharePayload == nil {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Theme.coral)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(preparingShare || systemSharePayload != nil)
                .accessibilityLabel("Share")

                AppreciationPrivacyMark(
                    visibility: gratitude.visibility,
                    acceptedAsPrivate: gratitude.acceptedAsPrivate
                )
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
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items) { activityType in
                let voice = AppreciationShareVoice.resolve(gratitude: gratitude, userId: auth.userId)
                let content = AppreciationShareContent(gratitude: gratitude, voice: voice)
                Analytics.appreciationShared(
                    appreciationId: gratitude.id,
                    channel: SocialShare.analyticsChannel(for: activityType),
                    voice: voice.rawValue,
                    // Feed share is link + caption (no 1080×1920 poster) for snappy UX.
                    hasCard: false,
                    hasPhoto: content.sharePhotoURL != nil
                )
            }
        }
    }

    private func presentSystemShare() async {
        guard !preparingShare, systemSharePayload == nil else { return }
        preparingShare = true
        defer { preparingShare = false }
        // Feed cards share caption + tappable link only — skip ImageRenderer poster
        // work (and photo download) so the sheet opens immediately.
        let voice = AppreciationShareVoice.resolve(gratitude: gratitude, userId: auth.userId)
        let content = AppreciationShareContent(gratitude: gratitude, voice: voice)
        let items = SocialShare.systemShareItems(content: content, cardImage: nil)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        systemSharePayload = SystemSharePayload(items: items)
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

    /// “Alex thanked Jordan” as one wrapping Text — avoids HStack gaps when names break.
    private var thankedHeadline: AttributedString {
        var author = AttributedString(gratitude.author?.displayName ?? "Someone")
        author.font = Theme.body(15, weight: .semibold)
        author.foregroundColor = Theme.textPrimary
        author.underlineStyle = []
        if gratitude.author != nil {
            author.link = URL(string: "openthanks-card://author")
        }

        var thanked = AttributedString(" thanked ")
        thanked.font = Theme.body(15)
        thanked.foregroundColor = Theme.textSecondary
        thanked.underlineStyle = []

        var recipient = AttributedString(gratitude.recipientDisplayName)
        recipient.font = Theme.body(15, weight: .semibold)
        recipient.foregroundColor = Theme.textPrimary
        recipient.underlineStyle = []
        if gratitude.recipient != nil {
            recipient.link = URL(string: "openthanks-card://recipient")
        }

        return author + thanked + recipient
    }

    private func handleThankedHeadlineURL(_ url: URL) -> OpenURLAction.Result {
        switch url.host {
        case "author":
            if let profile = gratitude.author {
                onOpenProfile?(profile)
                return .handled
            }
        case "recipient":
            if let profile = gratitude.recipient {
                onOpenProfile?(profile)
                return .handled
            }
        default:
            break
        }
        return .discarded
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

/// Observes the enclosing UIScrollView contentOffset (reliable on iOS 17; PreferenceKey
/// on LazyVStack often never updates while scrolling).
private struct FeedScrollOffsetReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator {
        var onChange: (CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard self.scrollView == nil else { return }
                guard let scroll = view.enclosingScrollView() else { return }
                self.scrollView = scroll
                self.observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scrollView, _ in
                    self?.onChange(scrollView.contentOffset.y)
                }
                self.onChange(scroll.contentOffset.y)
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView {
                return scroll
            }
            current = view.superview
        }
        return nil
    }
}

/// Compact people search under the Home brand row — opens profiles or invites
/// someone who isn't on OpenThanks yet (matches the web home search).
private struct HomeProfileSearch: View {
    var focused: FocusState<Bool>.Binding
    /// Reports whether the field has a non-empty query (keeps the bar visible while typing).
    var onQueryChange: ((Bool) -> Void)? = nil
    var onSelect: (Profile) -> Void
    var onInvite: (String) -> Void

    @Environment(UserBlockService.self) private var userBlocks
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
        .onChange(of: trimmed) { _, value in
            onQueryChange?(!value.isEmpty)
        }
        .onChange(of: focused.wrappedValue) { _, isFocused in
            if isFocused {
                onQueryChange?(!trimmed.isEmpty)
            }
        }
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

                TextField("Search for someone to thank", text: $query)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused(focused)
                    .submitLabel(.search)
                    .accessibilityLabel("Search for someone to thank")

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
        onQueryChange?(false)
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
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }

        do {
            let found = try await GratitudeService.searchProfiles(query: current)
            guard !Task.isCancelled else { return }
            results = userBlocks.filterProfiles(found)
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
