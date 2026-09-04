import SwiftUI

/// Route for posts we only know by id (e.g. notification taps).
struct GratitudeIdRoute: Hashable, Identifiable { let id: UUID }

/// Pending list pushed from Home / Notifications banners.
/// `highlightId` opens that item's share sheet (e.g. bounce / resend deep links).
struct PendingAppreciationsRoute: Hashable {
    var highlightId: UUID? = nil
}

/// Opens a profile on the host tab’s NavigationPath (e.g. after dismissing a sheet).
private struct OpenProfileKey: EnvironmentKey {
    static let defaultValue: ((Profile) -> Void)? = nil
}

extension EnvironmentValues {
    var openProfile: ((Profile) -> Void)? {
        get { self[OpenProfileKey.self] }
        set { self[OpenProfileKey.self] = newValue }
    }
}

extension View {
    /// Registers the app-wide push destinations. Apply once at the root of
    /// every NavigationStack so profiles and posts can be pushed from anywhere.
    func appDestinations() -> some View {
        self
            .navigationDestination(for: Profile.self) { UserProfileView(profile: $0) }
            .navigationDestination(for: Gratitude.self) { GratitudeDetailView(gratitude: $0) }
            .navigationDestination(for: GratitudeIdRoute.self) { GratitudeLoaderView(gratitudeId: $0.id) }
            .navigationDestination(for: PendingAppreciationsRoute.self) { route in
                PendingAppreciationsView(highlightId: route.highlightId)
            }
    }
}

/// An avatar that opens the person's profile when tapped — used everywhere
/// a profile image appears.
///
/// Prefer `onOpen` (or `path`) inside multi-column / split shells — bare
/// `NavigationLink(value:)` often fails to push when nested under
/// `NavigationSplitView`.
struct ProfileAvatarLink: View {
    let profile: Profile?
    var size: CGFloat = 40
    /// Programmatic open (iPad two-pane / nested chrome). When nil, uses NavigationLink.
    var onOpen: ((Profile) -> Void)? = nil

    var body: some View {
        if let profile {
            if let onOpen {
                Button {
                    onOpen(profile)
                } label: {
                    AvatarView(profile: profile, size: size)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(profile.displayName)'s profile")
            } else {
                NavigationLink(value: profile) {
                    AvatarView(profile: profile, size: size)
                }
                .buttonStyle(.plain)
            }
        } else {
            AvatarView(profile: nil, size: size)
        }
    }
}

/// Avatar + display name (and optional subtitle) that opens the profile.
/// Use on accept/reject and anywhere the name should be tappable too.
struct ProfilePersonLink<Subtitle: View>: View {
    let profile: Profile?
    var size: CGFloat = 40
    var nameFont: Font = Theme.body(16, weight: .semibold)
    var onOpen: ((Profile) -> Void)? = nil
    @ViewBuilder var subtitle: () -> Subtitle

    init(
        profile: Profile?,
        size: CGFloat = 40,
        nameFont: Font = Theme.body(16, weight: .semibold),
        onOpen: ((Profile) -> Void)? = nil,
        @ViewBuilder subtitle: @escaping () -> Subtitle
    ) {
        self.profile = profile
        self.size = size
        self.nameFont = nameFont
        self.onOpen = onOpen
        self.subtitle = subtitle
    }

    var body: some View {
        if let profile {
            if let onOpen {
                Button {
                    onOpen(profile)
                } label: {
                    personRow(profile: profile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(profile.displayName)'s profile")
            } else {
                NavigationLink(value: profile) {
                    personRow(profile: profile)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(profile.displayName)'s profile")
            }
        } else {
            personRow(profile: nil)
        }
    }

    private func personRow(profile: Profile?) -> some View {
        HStack(spacing: 10) {
            AvatarView(profile: profile, size: size)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayName ?? "Someone")
                    .font(nameFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                subtitle()
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension ProfilePersonLink where Subtitle == EmptyView {
    init(
        profile: Profile?,
        size: CGFloat = 40,
        nameFont: Font = Theme.body(16, weight: .semibold),
        onOpen: ((Profile) -> Void)? = nil
    ) {
        self.init(profile: profile, size: size, nameFont: nameFont, onOpen: onOpen) { EmptyView() }
    }
}

/// Loads a post by id, then shows accept/reject when it's still pending for
/// the signed-in user — otherwise the normal post detail screen.
struct GratitudeLoaderView: View {
    let gratitudeId: UUID
    var onOpenProfile: ((Profile) -> Void)? = nil
    @Environment(AuthService.self) private var auth
    @State private var gratitude: Gratitude?
    @State private var failed = false
    @State private var showPayItForward = false
    @State private var showCompose = false

    var body: some View {
        Group {
            if let gratitude {
                if isPendingForCurrentUser(gratitude) {
                    PendingAppreciationReviewView(gratitude: gratitude) { accepted in
                        withAnimation(Motion.note) {
                            self.gratitude = accepted
                            showPayItForward = true
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        if showPayItForward {
                            PayItForwardNudgeCard(
                                fromName: gratitude.author?.fullName
                                    ?? gratitude.author?.displayName,
                                onThankSomeone: {
                                    Analytics.capture(
                                        "pay_it_forward_tapped",
                                        [
                                            "source": "claim_accept",
                                            "parent_gratitude_id": gratitude.id.uuidString.lowercased(),
                                        ]
                                    )
                                    showCompose = true
                                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                                },
                                onDismiss: {
                                    withAnimation(Motion.note) {
                                        showPayItForward = false
                                    }
                                    AppStoreReviewPrompt.scheduleAfterPostAcceptMoment()
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        GratitudeDetailView(
                            gratitude: gratitude,
                            onOpenProfile: onOpenProfile
                        )
                    }
                }
            } else if failed {
                VStack(spacing: 10) {
                    HeartMark(size: 40)
                    Text("This appreciation isn't available.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            } else {
                ProgressView().tint(Theme.coral)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .composeCover(isPresented: $showCompose) {
            ComposeView(
                inspiredByGratitudeId: gratitude?.id,
                inspiredByAuthorName: gratitude?.author?.fullName
                    ?? gratitude?.author?.displayName,
                analyticsSource: "post_accept_pay_it_forward"
            )
        }
        .task {
            do { gratitude = try await GratitudeService.gratitude(id: gratitudeId) }
            catch {
                if !error.isCancellation { failed = true }
            }
        }
    }

    private func isPendingForCurrentUser(_ gratitude: Gratitude) -> Bool {
        guard gratitude.status == .pending else { return false }
        guard let userId = auth.userId else { return false }
        guard gratitude.authorId != userId else { return false }

        if gratitude.recipientId == userId { return true }

        if let email = auth.currentProfile?.email?.lowercased(),
           let recipientEmail = gratitude.recipientEmail?.lowercased(),
           email == recipientEmail {
            return true
        }

        if let phone = auth.currentProfile?.phone,
           let recipientPhone = gratitude.recipientPhone,
           phone == recipientPhone {
            return true
        }

        return false
    }
}

/// Full-screen, pinch-zoomable image viewer.
struct FullScreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            CachedAsyncImage(url: url, maxPixelSize: RemoteImageCache.fullScreenMaxPixelSize) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification.simultaneously(with: drag))
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
            } placeholder: {
                ProgressView().tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding(20)
        }
        .statusBarHidden()
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, lastScale * value.magnification)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 { withAnimation(.spring(duration: 0.3)) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                } else {
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
                }
            }
    }

    private func reset() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}
