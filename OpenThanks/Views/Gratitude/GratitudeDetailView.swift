import SwiftUI

/// Holds activity items for the system share sheet so presentation can’t race an empty array.
private struct SystemSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Single-post screen: the full appreciation plus share actions,
/// mirroring the web post page (openthanks.com/for/{slug}).
struct GratitudeDetailView: View {
    @State var gratitude: Gratitude
    /// When set (iPad two-pane), open profiles via the parent NavigationPath.
    var onOpenProfile: ((Profile) -> Void)? = nil
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var isHearted = false
    @State private var fullScreenImageURL: URL?
    @State private var linkCopied = false
    @State private var shareHint: String?
    @State private var shareCardImage: UIImage?
    @State private var linkStickerImage: UIImage?
    @State private var preparingShare = false
    @State private var preparingPreview = false
    @State private var systemSharePayload: SystemSharePayload?
    @State private var showReportSheet = false

    private var shareVoice: AppreciationShareVoice {
        AppreciationShareVoice.resolve(gratitude: gratitude, userId: auth.userId)
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
            VStack(spacing: 20) {
                postCard
                    .softNoteReveal()
                shareCard
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items)
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
                    onOpenProfile: onOpenProfile
                )

                Spacer(minLength: 0)
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

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(shareSectionTitle)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("A photo (or poster), the beginning of the note, and a link people can tap.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            sharePreview

            HStack(spacing: 10) {
                shareButton(
                    title: "Instagram",
                    subtitle: "Stories",
                    systemImage: "camera.filters"
                ) {
                    Task { await share(.instagramStories) }
                }
                shareButton(
                    title: "LinkedIn",
                    subtitle: "Post",
                    systemImage: "briefcase.fill"
                ) {
                    Task { await share(.linkedIn) }
                }
                shareButton(
                    title: "X",
                    subtitle: "Post",
                    systemImage: "bird.fill"
                ) {
                    Task { await share(.x) }
                }
            }

            ShareActionRow(
                title: "Share",
                systemImage: "square.and.arrow.up",
                subtitle: "Photo or poster, caption, and link — Messages, Mail, and more",
                showSpinner: preparingShare && systemSharePayload == nil
            ) {
                Task { await presentSystemShare() }
            }
            .disabled(preparingShare)

            Button {
                UIPasteboard.general.string = shareContent.url.absoluteString
                withAnimation { linkCopied = true }
                flashHint("Link copied")
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { linkCopied = false }
                }
            } label: {
                Label(
                    linkCopied ? "Link copied" : "Copy link to appreciation",
                    systemImage: linkCopied ? "checkmark" : "doc.on.doc"
                )
                .font(Theme.body(14, weight: .medium))
                .foregroundStyle(linkCopied ? Theme.coral : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surfaceRaised, in: Capsule())
            }

            if let shareHint {
                Text(shareHint)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.coral)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(18)
        .card()
    }

    private var shareSectionTitle: String {
        switch shareVoice {
        case .author: return "Share your appreciation"
        case .recipient: return "Share this appreciation"
        case .viewer: return "Share this moment"
        }
    }

    @ViewBuilder
    private var sharePreview: some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(width: 148, height: 264)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
            .accessibilityLabel("Share preview")
            Spacer(minLength: 0)
        }
    }

    private func shareButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.coralLight)
                    .frame(width: 42, height: 42)
                    .background(Theme.coral.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.coral.opacity(0.25)))
                Text(title)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
        }
        .buttonStyle(.plain)
        .disabled(preparingShare)
    }

    // MARK: Share actions

    /// Loads the composed visual for the live preview (and system / Stories share).
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

    /// Stories needs the sticker; LinkedIn / X only need copy.
    private func prepareStoriesAssetsIfNeeded() async {
        await prepareSharePreviewIfNeeded()
        if linkStickerImage == nil {
            linkStickerImage = AppreciationShareRenderer.linkSticker(for: shareContent)
        }
    }

    private func share(_ destination: SocialShare.Destination) async {
        preparingShare = true
        defer { preparingShare = false }

        if destination == .instagramStories {
            await prepareStoriesAssetsIfNeeded()
        }

        let outcome = await SocialShare.share(
            destination,
            content: shareContent,
            cardImage: shareCardImage,
            linkSticker: linkStickerImage,
            openURL: openURL
        )
        switch outcome {
        case .opened(let hint):
            flashHint(hint)
        }
        Analytics.capture("appreciation_shared", [
            "channel": destination.rawValue,
            "voice": shareVoice.rawValue,
            "has_photo": shareContent.sharePhotoURL != nil,
            "has_card": shareCardImage != nil,
        ])
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
        systemSharePayload = SystemSharePayload(items: items)
        Analytics.capture("appreciation_shared", [
            "channel": "system_sheet",
            "voice": shareVoice.rawValue,
            "has_photo": content.sharePhotoURL != nil,
            "has_card": shareCardImage != nil,
        ])
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
