import SwiftUI

/// Profile pushed from the hearts sheet. A distinct type so it doesn’t collide
/// with the stack’s existing `navigationDestination(for: Profile.self)`.
private struct HeartedProfileRoute: Hashable {
    let profile: Profile
}

/// Single-post screen: the full appreciation plus share actions,
/// mirroring the web post page (openthanks.com/for/{slug}).
struct GratitudeDetailView: View {
    @State var gratitude: Gratitude
    /// When set (iPad two-pane), open profiles via the parent NavigationPath.
    var onOpenProfile: ((Profile) -> Void)? = nil
    @Environment(AuthService.self) private var auth
    @Environment(UserBlockService.self) private var userBlocks
    @Environment(\.dismiss) private var dismiss

    @State private var isHearted = false
    @State private var fullScreenImageURL: URL?
    @State private var linkCopied = false
    @State private var shareHint: String?
    @State private var shareCardImage: UIImage?
    @State private var preparingShare = false
    @State private var preparingPreview = false
    @State private var systemSharePayload: SystemSharePayload?
    @State private var showReportSheet = false
    @State private var confirmBlock = false
    @State private var blocking = false
    @State private var blockError: String?
    /// Set after the hearts sheet dismisses, so Back returns to this appreciation.
    @State private var heartedProfile: HeartedProfileRoute?

    private var shareVoice: AppreciationShareVoice {
        AppreciationShareVoice.resolve(gratitude: gratitude, userId: auth.userId)
    }

    private var canBlockAuthor: Bool {
        guard let userId = auth.userId else { return false }
        return gratitude.authorId != userId
    }

    private var authorDisplayName: String {
        gratitude.author?.displayName ?? "author"
    }

    private var shareContent: AppreciationShareContent {
        AppreciationShareContent(gratitude: gratitude, voice: shareVoice)
    }

    private var rippleChipTitle: String {
        if let raw = gratitude.inspiredByParent?.author?.displayName {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                let first = name.split(separator: " ").first.map(String.init) ?? name
                return "Part of \(first)’s ripple"
            }
        }
        return "Part of a ripple"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                postCard
                    .softNoteReveal()
                shareStrip
                    .softNoteReveal(delay: 0.08)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .tabChromeBottomPadding()
            .readableWidth()
        }
        .background(Theme.background)
        .navigationTitle("Appreciation")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $heartedProfile) { route in
            UserProfileView(profile: route.profile)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if canBlockAuthor {
                        Button(role: .destructive) {
                            confirmBlock = true
                        } label: {
                            Label("Block \(authorDisplayName)", systemImage: "hand.raised")
                        }
                    }
                    Button(role: .destructive) {
                        showReportSheet = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("More")
            }
        }
        .sheet(isPresented: $showReportSheet) {
            ReportContentSheet(
                target: .gratitude(gratitude.id),
                title: "Report this appreciation if it violates our community standards."
            )
        }
        .alert("Block \(authorDisplayName)?", isPresented: $confirmBlock) {
            Button("Cancel", role: .cancel) {}
            Button("Block", role: .destructive) {
                Task { await blockAuthor() }
            }
        } message: {
            Text("You won’t see their appreciations or profile in your feeds. They won’t be notified.")
        }
        .alert("Couldn’t block", isPresented: Binding(
            get: { blockError != nil },
            set: { if !$0 { blockError = nil } }
        )) {
            Button("OK", role: .cancel) { blockError = nil }
        } message: {
            Text(blockError ?? "")
        }
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items) { activityType in
                trackShare(channel: SocialShare.analyticsChannel(for: activityType))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissTransientSheets)) { _ in
            systemSharePayload = nil
        }
        .task {
            await loadHearted()
            if auth.userId == gratitude.recipientId {
                WarmHaptics.received()
            }
            await prepareSharePreviewIfNeeded()
        }
    }

    // MARK: Post

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProfileAvatarLink(
                    profile: gratitude.author,
                    size: 44,
                    onOpen: onOpenProfile
                )
                VStack(alignment: .leading, spacing: 1) {
                    (Text(gratitude.author?.displayName ?? "Someone")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                     + Text(" thanked ").font(Theme.body(15)).foregroundStyle(Theme.textSecondary)
                     + Text(gratitude.recipientDisplayName)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary))
                    if let date = gratitude.displayDate {
                        Text(date, format: .dateTime.month(.wide).day().year())
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if let recipient = gratitude.recipient {
                    ProfileAvatarLink(
                        profile: recipient,
                        size: 32,
                        onOpen: onOpenProfile
                    )
                }
            }

            LinkifiedText(
                text: gratitude.message,
                font: Theme.display(19, weight: .regular),
                foreground: Theme.textPrimary
            )
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            if let url = gratitude.mediaURL {
                let isVideo = gratitude.mediaType?.lowercased().hasPrefix("video") == true
                if isVideo {
                    FlexiblePostMedia(url: url, mediaType: gratitude.mediaType, maxHeight: 520)
                } else {
                    Button { fullScreenImageURL = url } label: {
                        FlexiblePostImage(url: url, maxHeight: 520)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let parentId = gratitude.inspiredByGratitudeId {
                NavigationLink(value: GratitudeIdRoute(id: parentId)) {
                    HStack(spacing: 8) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 13, weight: .semibold))
                        Text(rippleChipTitle)
                            .font(Theme.body(13, weight: .semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .foregroundStyle(Theme.coral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.coral.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.coral.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rippleChipTitle)
            }

            HStack(spacing: 12) {
                Button(action: toggleHeart) {
                    HStack(spacing: 5) {
                        Image(systemName: isHearted ? "heart.fill" : "heart")
                            .foregroundStyle(isHearted ? Theme.coral : Theme.textSecondary)
                        Text("\(gratitude.heartCount)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.body(15, weight: .medium))
                }
                .accessibilityLabel(isHearted ? "Remove heart" : "Heart")

                HeartedByView(
                    gratitudeId: gratitude.id,
                    heartCount: gratitude.heartCount,
                    onOpenProfile: onOpenProfile ?? { heartedProfile = HeartedProfileRoute(profile: $0) }
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
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(Theme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(preparingShare)
                .accessibilityLabel("Share")

                if gratitude.visibility == .private {
                    Label("Private", systemImage: "lock.fill")
                        .font(Theme.body(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .padding(18)
        .card()
    }

    // MARK: Share

    /// Compact strip under the card — preview + one system Share action (no per-app grid).
    private var shareStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shareSectionTitle)
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 14) {
                sharePreviewThumb

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        Task { await presentSystemShare() }
                    } label: {
                        HStack(spacing: 8) {
                            if preparingShare && systemSharePayload == nil {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("Share")
                                .font(Theme.body(15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.ctaGradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(preparingShare)
                    .accessibilityLabel("Share appreciation")

                    Button {
                        UIPasteboard.general.string = shareContent.url.absoluteString
                        trackShare(channel: "copy_link")
                        withAnimation { linkCopied = true }
                        flashHint("Link copied")
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { linkCopied = false }
                        }
                    } label: {
                        Label(
                            linkCopied ? "Link copied" : "Copy link",
                            systemImage: linkCopied ? "checkmark" : "link"
                        )
                        .font(Theme.body(13, weight: .medium))
                        .foregroundStyle(linkCopied ? Theme.coral : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let shareHint {
                Text(shareHint)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .card()
    }

    private var shareSectionTitle: String {
        switch shareVoice {
        case .author: return "Share your appreciation"
        case .recipient: return "Share this appreciation"
        case .viewer: return "Share this moment"
        }
    }

    private var sharePreviewThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised)

            if let shareCardImage {
                Image(uiImage: shareCardImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if preparingPreview {
                ProgressView()
                    .tint(Theme.coral)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 64, height: 112)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .accessibilityLabel("Share preview")
        .accessibilityHidden(true)
    }

    // MARK: Share actions

    /// Loads the composed visual for the system share sheet preview.
    private func prepareSharePreviewIfNeeded() async {
        guard shareCardImage == nil, !preparingPreview else { return }
        preparingPreview = true
        defer { preparingPreview = false }
        let content = shareContent
        shareCardImage = await AppreciationShareRenderer.storyImage(for: content)
        if shareCardImage == nil {
            await Task.yield()
            shareCardImage = await AppreciationShareRenderer.storyImage(for: content)
        }
    }

    private func trackShare(channel: String) {
        Analytics.appreciationShared(
            appreciationId: gratitude.id,
            channel: channel,
            voice: shareVoice.rawValue,
            hasCard: shareCardImage != nil,
            hasPhoto: shareContent.sharePhotoURL != nil
        )
    }

    private func presentSystemShare() async {
        preparingShare = true
        defer { preparingShare = false }
        await prepareSharePreviewIfNeeded()
        let content = shareContent
        let items = SocialShare.systemShareItems(
            content: content,
            cardImage: shareCardImage
        )
        // Present via Identifiable payload so the sheet is created with items already set.
        // `appreciation_shared` fires from the sheet's completion handler, not here,
        // so a cancelled share is not counted.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        systemSharePayload = SystemSharePayload(items: items)
    }

    private func flashHint(_ message: String?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            shareHint = message
        }
        guard message != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeInOut(duration: 0.2)) {
                if shareHint == message { shareHint = nil }
            }
        }
    }

    // MARK: Hearts

    private func blockAuthor() async {
        guard let blockerId = auth.userId, canBlockAuthor, !blocking else { return }
        blocking = true
        defer { blocking = false }
        do {
            try await userBlocks.block(userId: gratitude.authorId, blockerId: blockerId)
            dismiss()
        } catch {
            blockError = error.localizedDescription
        }
    }

    private func loadHearted() async {
        guard let userId = auth.userId else { return }
        let hearted = (try? await GratitudeService.myHearts(userId: userId,
                                                            among: [gratitude.id])) ?? []
        isHearted = hearted.contains(gratitude.id)
    }

    private func toggleHeart() {
        guard let userId = auth.userId else { return }
        let wasHearted = isHearted
        isHearted.toggle()
        gratitude.hearts = [CountHolder(count: max(0, gratitude.heartCount + (wasHearted ? -1 : 1)))]
        Task {
            do {
                if wasHearted {
                    try await GratitudeService.unheart(gratitudeId: gratitude.id, userId: userId)
                } else {
                    try await GratitudeService.heart(gratitudeId: gratitude.id, userId: userId, authorId: gratitude.authorId)
                }
            } catch {
                isHearted = wasHearted
                gratitude.hearts = [CountHolder(count: max(0, gratitude.heartCount + (wasHearted ? 1 : -1)))]
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
