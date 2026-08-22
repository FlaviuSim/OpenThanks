import SwiftUI
import UIKit
import LinkPresentation

// MARK: - Share voice & content

/// Whose perspective the share caption should use.
enum AppreciationShareVoice: String {
    case author
    case recipient
    case viewer

    static func resolve(gratitude: Gratitude, userId: UUID?) -> AppreciationShareVoice {
        guard let userId else { return .viewer }
        if userId == gratitude.authorId { return .author }
        if let recipientId = gratitude.recipientId, userId == recipientId { return .recipient }
        return .viewer
    }
}

/// Copy + assets for sharing an accepted appreciation outside OpenThanks.
struct AppreciationShareContent {
    let url: URL
    let authorName: String
    let recipientName: String
    let message: String
    let mediaURL: URL?
    let mediaType: String?
    let voice: AppreciationShareVoice

    init(gratitude: Gratitude, voice: AppreciationShareVoice = .viewer) {
        url = gratitude.webURL
        authorName = gratitude.author?.displayName ?? "Someone"
        recipientName = gratitude.recipientDisplayName
        message = gratitude.message.trimmingCharacters(in: .whitespacesAndNewlines)
        mediaURL = gratitude.mediaURL
        mediaType = gratitude.mediaType
        self.voice = voice
    }

    /// Image attachment suitable for the share visual (skips video).
    var sharePhotoURL: URL? {
        guard let mediaURL else { return nil }
        if mediaType?.lowercased().hasPrefix("video") == true { return nil }
        return mediaURL
    }

    /// Short quote for cards / captions.
    func quoteSnippet(maxLength: Int = 140) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\n+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max(0, maxLength - 3))
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    var quoteSnippet: String { quoteSnippet(maxLength: 140) }

    private var leadIn: String {
        switch voice {
        case .author:
            return "I'm so grateful for \(recipientName)"
        case .recipient:
            return "So kind of \(authorName) to send me a gratitude on OpenThanks"
        case .viewer:
            return "\(authorName) thanked \(recipientName) on OpenThanks:"
        }
    }

    private var closer: String {
        switch voice {
        case .author:
            return "The full note is on OpenThanks."
        case .recipient:
            return "Read the full appreciation."
        case .viewer:
            return "Read it on OpenThanks."
        }
    }

    /// Helper-framed caption without URL — LinkedIn paste, X `text`, system share text.
    var socialCaptionBody: String {
        """
        \(leadIn)

        “\(quoteSnippet)”

        \(closer)
        """
    }

    /// Caption with URL — used when a channel needs both in one string.
    var socialCaption: String {
        """
        \(socialCaptionBody)

        \(url.absoluteString)
        """
    }

    /// Host + path for display on the link sticker (no scheme).
    var displayLink: String {
        let host = url.host ?? "openthanks.com"
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return host }
        return "\(host)/\(path)"
    }

    var linkMetadataTitle: String {
        switch voice {
        case .author:
            return "Appreciation for \(recipientName)"
        case .recipient:
            return "Appreciation from \(authorName)"
        case .viewer:
            return "Appreciation on OpenThanks"
        }
    }
}

// MARK: - Story visual (1080×1920)

/// Full-bleed photo with quote overlay, or typographic OpenThanks poster when no photo.
struct AppreciationShareCardView: View {
    let content: AppreciationShareContent
    var photo: UIImage? = nil

    private var hasPhoto: Bool { photo != nil }
    private let coral = Color(hex: 0xE07A5F)

    var body: some View {
        ZStack {
            if let photo {
                photoBackground(photo)
            } else {
                posterBackground
            }

            VStack(spacing: 0) {
                if hasPhoto {
                    Spacer(minLength: 0)
                    photoQuoteOverlay
                } else {
                    posterContent
                }
            }
            .padding(.horizontal, 56)
            .padding(.top, hasPhoto ? 64 : 96)
            .padding(.bottom, hasPhoto ? 120 : 96)
        }
        .frame(width: 1080, height: 1920)
        .clipped()
    }

    private func photoBackground(_ photo: UIImage) -> some View {
        ZStack {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 1080, height: 1920)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.15),
                    .clear,
                    .clear,
                    .black.opacity(0.72),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var posterBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.08, blue: 0.08),
                    Color(red: 0.16, green: 0.11, blue: 0.10),
                    Color(red: 0.22, green: 0.12, blue: 0.10),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(coral.opacity(0.28))
                .frame(width: 720, height: 720)
                .blur(radius: 70)
                .offset(x: 240, y: 560)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 520, height: 520)
                .blur(radius: 40)
                .offset(x: -280, y: -480)
        }
    }

    private var photoQuoteOverlay: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("“\(content.quoteSnippet(maxLength: 120))”")
                .font(.system(size: 36, weight: .regular, design: .serif))
                .foregroundStyle(.white)
                .lineSpacing(8)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .fixedSize(horizontal: false, vertical: true)

            Text("OpenThanks")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .tracking(1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var posterContent: some View {
        let fullMessage = content.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteFontSize = posterQuoteFontSize(for: fullMessage.count)

        return VStack(alignment: .leading, spacing: 0) {
            Text("OpenThanks")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(0.5)

            Rectangle()
                .fill(coral)
                .frame(width: 72, height: 4)
                .padding(.top, 28)
                .padding(.bottom, 48)

            Text("“\(fullMessage)”")
                .font(.system(size: quoteFontSize, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
                .lineSpacing(quoteFontSize > 32 ? 10 : 6)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 40)

            Text(posterAttribution)
                .font(.system(size: 26, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Scale quote type so the full message fits the Stories poster.
    private func posterQuoteFontSize(for characterCount: Int) -> CGFloat {
        switch characterCount {
        case ...120: return 46
        case ...220: return 38
        case ...360: return 32
        case ...520: return 28
        default: return 24
        }
    }

    private var posterAttribution: String {
        switch content.voice {
        case .author:
            return "For \(content.recipientName)"
        case .recipient:
            return "From \(content.authorName)"
        case .viewer:
            return "\(content.authorName) → \(content.recipientName)"
        }
    }
}

/// Link pill used only as the Instagram Stories sticker (tappable via linkURL).
struct AppreciationShareLinkBar: View {
    let displayLink: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "link")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(hex: 0xE07A5F))
                .frame(width: 44, height: 44)
                .background(.white, in: Circle())

            Text(displayLink)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.11))
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: 0xE07A5F))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .frame(maxWidth: .infinity)
    }
}

struct AppreciationShareLinkStickerView: View {
    let content: AppreciationShareContent

    var body: some View {
        AppreciationShareLinkBar(displayLink: content.displayLink)
            .frame(width: 920)
    }
}

enum AppreciationShareRenderer {
    @MainActor
    static func storyImage(for content: AppreciationShareContent, photo: UIImage? = nil) -> UIImage? {
        let view = AppreciationShareCardView(content: content, photo: photo)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        if let image = renderer.uiImage { return image }
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1920)
        return renderer.uiImage
    }

    /// Loads an attached photo (if any) then renders the share visual.
    @MainActor
    static func storyImage(for content: AppreciationShareContent) async -> UIImage? {
        var photo: UIImage?
        if let url = content.sharePhotoURL {
            photo = await RemoteImageCache.load(url, maxPixelSize: 1_400)
        }
        if let image = storyImage(for: content, photo: photo) { return image }
        await Task.yield()
        return storyImage(for: content, photo: photo)
    }

    @MainActor
    static func linkSticker(for content: AppreciationShareContent) -> UIImage? {
        let view = AppreciationShareLinkStickerView(content: content)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: 920, height: 88)
        if let image = renderer.uiImage { return image }
        renderer.proposedSize = ProposedViewSize(width: 920, height: 88)
        return renderer.uiImage
    }
}

// MARK: - System share sheet

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType] = []

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.excludedActivityTypes = excludedActivityTypes
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Rich link metadata so Messages / Mail show a nicer preview when possible.
final class AppreciationLinkMetadata: NSObject, UIActivityItemSource {
    let content: AppreciationShareContent
    let image: UIImage?

    init(content: AppreciationShareContent, image: UIImage?) {
        self.content = content
        self.image = image
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        content.url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        content.url
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = content.url
        metadata.url = content.url
        metadata.title = content.linkMetadataTitle
        if let image {
            metadata.imageProvider = NSItemProvider(object: image)
        }
        return metadata
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        content.linkMetadataTitle
    }
}

// MARK: - Channel helpers

enum SocialShare {
    enum Destination: String {
        case instagramStories = "instagram_stories"
        case linkedIn = "linkedin"
        case x = "x"
    }

    enum Outcome {
        /// Opened a native destination or web share intent.
        case opened(hint: String)
    }

    @MainActor
    static func share(
        _ destination: Destination,
        content: AppreciationShareContent,
        cardImage: UIImage?,
        linkSticker: UIImage?,
        openURL: OpenURLAction
    ) async -> Outcome {
        switch destination {
        case .instagramStories:
            return await shareInstagramStories(
                content: content,
                cardImage: cardImage,
                linkSticker: linkSticker,
                openURL: openURL
            )
        case .linkedIn:
            return shareLinkedIn(content: content)
        case .x:
            return shareX(content: content, openURL: openURL)
        }
    }

    /// LinkedIn `share-offsite` only takes a URL; caption cannot be prefilled — copy for paste.
    @MainActor
    private static func shareLinkedIn(content: AppreciationShareContent) -> Outcome {
        UIPasteboard.general.string = content.socialCaptionBody
        var components = URLComponents(string: "https://www.linkedin.com/sharing/share-offsite/")!
        components.queryItems = [URLQueryItem(name: "url", value: content.url.absoluteString)]
        guard let url = components.url else {
            return .opened(hint: "Caption copied — paste into LinkedIn with your link.")
        }
        UIApplication.shared.open(url)
        return .opened(
            hint: "Caption copied — paste it into your LinkedIn post. The link preview is already attached."
        )
    }

    @MainActor
    private static func shareX(
        content: AppreciationShareContent,
        openURL: OpenURLAction
    ) -> Outcome {
        var components = URLComponents(string: "https://twitter.com/intent/tweet")!
        components.queryItems = [
            URLQueryItem(name: "text", value: content.socialCaptionBody),
            URLQueryItem(name: "url", value: content.url.absoluteString),
        ]
        if let url = components.url {
            openURL(url)
            return .opened(hint: "X opened with your appreciation ready to post.")
        }
        UIPasteboard.general.string = content.socialCaption
        return .opened(hint: "Caption & link copied — paste into X.")
    }

    @MainActor
    private static func shareInstagramStories(
        content: AppreciationShareContent,
        cardImage: UIImage?,
        linkSticker: UIImage?,
        openURL: OpenURLAction
    ) async -> Outcome {
        let source = Bundle.main.bundleIdentifier ?? "com.openthanks.app"
        let storiesURL = URL(string: "instagram-stories://share?source_application=\(source)")!

        if let cardImage,
           let backgroundPNG = cardImage.pngData(),
           UIApplication.shared.canOpenURL(storiesURL) {
            var payload: [String: Any] = [
                "com.instagram.sharedSticker.backgroundImage": backgroundPNG,
                "com.instagram.sharedSticker.contentURL": content.url.absoluteString,
                "com.instagram.sharedSticker.linkURL": content.url.absoluteString,
                "com.instagram.sharedSticker.linkText": "OpenThanks",
                "com.instagram.sharedSticker.backgroundTopColor": "#1F1614",
                "com.instagram.sharedSticker.backgroundBottomColor": "#E07A5F",
            ]
            if let stickerPNG = linkSticker?.pngData() {
                payload["com.instagram.sharedSticker.stickerImage"] = stickerPNG
            }

            UIPasteboard.general.setItems(
                [payload],
                options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
            )
            openURL(storiesURL)
            return .opened(
                hint: "Drag the link sticker onto your story so people can tap through."
            )
        }

        UIPasteboard.general.string = content.socialCaption
        if let app = URL(string: "instagram://app"),
           UIApplication.shared.canOpenURL(app) {
            openURL(app)
            return .opened(hint: "Caption & link copied — paste into your Instagram post or story.")
        }
        openURL(URL(string: "https://www.instagram.com")!)
        return .opened(hint: "Caption & link copied — paste into Instagram.")
    }

    /// System share: composed visual + helper caption (no URL string) + tappable link metadata.
    @MainActor
    static func systemShareItems(
        content: AppreciationShareContent,
        cardImage: UIImage?
    ) -> [Any] {
        var items: [Any] = [
            content.socialCaptionBody,
            AppreciationLinkMetadata(content: content, image: cardImage),
        ]
        if let cardImage {
            items.insert(cardImage, at: 0)
        }
        return items
    }
}
