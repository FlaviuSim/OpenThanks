import SwiftUI

/// Single-post screen: the full appreciation plus share actions,
/// mirroring the web post page (openthanks.com/for/{slug}).
struct GratitudeDetailView: View {
    @State var gratitude: Gratitude
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var isHearted = false
    @State private var fullScreenImageURL: URL?
    @State private var linkCopied = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                postCard
                shareCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .background(Theme.background)
        .navigationTitle("Appreciation")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $fullScreenImageURL) { url in
            FullScreenImageView(url: url)
        }
        .task { await loadHearted() }
    }

    // MARK: Post

    private var postCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProfileAvatarLink(profile: gratitude.author, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    (Text(gratitude.author?.displayName ?? "Someone")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                     + Text(" thanked ").font(Theme.body(15)).foregroundStyle(Theme.textSecondary)
                     + Text(gratitude.recipientDisplayName)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary))
                    if let date = gratitude.createdAt {
                        Text(date, format: .dateTime.month(.wide).day().year())
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if let recipient = gratitude.recipient {
                    ProfileAvatarLink(profile: recipient, size: 32)
                }
            }

            Text(gratitude.message)
                .font(Theme.display(19, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            if let url = gratitude.mediaURL, gratitude.mediaType?.hasPrefix("video") != true {
                Button { fullScreenImageURL = url } label: {
                    FlexiblePostImage(url: url, maxHeight: 520)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 18) {
                Button(action: toggleHeart) {
                    HStack(spacing: 5) {
                        Image(systemName: isHearted ? "heart.fill" : "heart")
                            .foregroundStyle(isHearted ? Theme.coral : Theme.textSecondary)
                        Text("\(gratitude.heartCount)")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.body(15, weight: .medium))
                }
                Spacer()
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
        VStack(spacing: 14) {
            Text("Spread the positivity")
                .font(Theme.body(14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 10) {
                shareButton(monogram: "IG", name: "Instagram") { shareToInstagram() }
                shareButton(monogram: "f", name: "Facebook") {
                    share(via: "https://www.facebook.com/sharer/sharer.php?u=")
                }
                shareButton(monogram: "in", name: "LinkedIn") {
                    share(via: "https://www.linkedin.com/sharing/share-offsite/?url=")
                }
            }

            Button {
                UIPasteboard.general.url = gratitude.webURL
                withAnimation { linkCopied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { linkCopied = false }
                }
            } label: {
                Label(linkCopied ? "Link copied" : "Copy link",
                      systemImage: linkCopied ? "checkmark" : "link")
                    .font(Theme.body(14, weight: .medium))
                    .foregroundStyle(linkCopied ? Theme.coral : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.surfaceRaised, in: Capsule())
            }
        }
        .padding(18)
        .card()
    }

    private func shareButton(monogram: String, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(monogram)
                    .font(Theme.display(15, weight: .bold))
                    .foregroundStyle(Theme.coralLight)
                    .frame(width: 42, height: 42)
                    .background(Theme.coral.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Theme.coral.opacity(0.25)))
                Text(name)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline))
        }
    }

    private func share(via prefix: String) {
        let encoded = gratitude.webURL.absoluteString
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: prefix + encoded) { openURL(url) }
    }

    /// Instagram has no web share intent — same as the web app, copy the
    /// link and hand off to Instagram so it can be pasted in a story or DM.
    private func shareToInstagram() {
        UIPasteboard.general.url = gratitude.webURL
        withAnimation { linkCopied = true }
        openURL(URL(string: "instagram://app")!) { accepted in
            if !accepted { openURL(URL(string: "https://www.instagram.com")!) }
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
                    try await GratitudeService.heart(gratitudeId: gratitude.id, userId: userId)
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
