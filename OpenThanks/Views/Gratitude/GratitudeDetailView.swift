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
    @State private var systemSharePayload: SystemSharePayload?

    private var shareContent: AppreciationShareContent {
        AppreciationShareContent(gratitude: gratitude)
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
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .sheet(item: $systemSharePayload) { payload in
            ActivityShareView(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .task {
            await loadHearted()
            if auth.userId == gratitude.recipientId {
                WarmHaptics.received()
            }
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
                Text("Spread the positivity")
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Share with a clear OpenThanks link people can tap.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
            }

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
                    subtitle: "Link",
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
                title: "Share photo & link",
                systemImage: "square.and.arrow.up",
                subtitle: "Messages, Mail, Instagram, and any other app"
            ) {
                Task { await presentSystemShare() }
            }

            Button {
                UIPasteboard.general.string = shareContent.caption
                withAnimation { linkCopied = true }
                flashHint("Caption & link copied")
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { linkCopied = false }
                }
            } label: {
                Label(
                    linkCopied ? "Caption copied" : "Copy caption & link",
                    systemImage: linkCopied ? "checkmark" : "link"
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

    private func prepareShareCardIfNeeded() async {
        guard shareCardImage == nil || linkStickerImage == nil else { return }
        preparingShare = true
        defer { preparingShare = false }
        let content = shareContent
        if shareCardImage == nil {
            shareCardImage = await AppreciationShareRenderer.storyImage(for: content)
        }
        if linkStickerImage == nil {
            linkStickerImage = AppreciationShareRenderer.linkSticker(for: content)
        }
    }

    private func share(_ destination: SocialShare.Destination) async {
        await prepareShareCardIfNeeded()
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
            "has_card": shareCardImage != nil,
        ])
    }

    private func presentSystemShare() async {
        preparingShare = true
        defer { preparingShare = false }
        let content = shareContent
        var postPhoto: UIImage?
        if let url = content.sharePhotoURL {
            postPhoto = await RemoteImageCache.load(url, maxPixelSize: 1_600)
        }
        if postPhoto == nil {
            if shareCardImage == nil {
                shareCardImage = await AppreciationShareRenderer.storyImage(for: content)
            }
            // ImageRenderer can return nil on a cold first pass — yield and retry once.
            if shareCardImage == nil {
                await Task.yield()
                shareCardImage = await AppreciationShareRenderer.storyImage(for: content)
            }
        }
        let items = SocialShare.systemShareItems(
            content: content,
            postPhoto: postPhoto,
            cardImage: shareCardImage
        )
        // Present via Identifiable payload so the sheet is created with items already set.
        // Splitting `items` + `isPresented` races and yields a blank UIActivityViewController.
        systemSharePayload = SystemSharePayload(items: items)
        Analytics.capture("appreciation_shared", [
            "channel": "system_sheet",
            "has_photo": postPhoto != nil,
            "has_card": postPhoto == nil && shareCardImage != nil,
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
