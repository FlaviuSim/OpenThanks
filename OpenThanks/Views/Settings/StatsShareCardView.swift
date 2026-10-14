import SwiftUI
import UIKit

/// Data for the shareable Stats pride poster.
struct StatsShareContent {
    let streak: Int
    let bestStreak: Int
    let sentCount: Int
    let acceptedCount: Int

    /// Short share link — `openthanks.com/app` (not the long App Store URL).
    var inviteURL: URL { AppConfig.appLandingURL }

    var displayInviteLink: String { "openthanks.com/app" }

    /// Proud caption for the system share sheet (includes short App invite).
    var shareCaption: String {
        let body: String
        if streak > 0 {
            let unit = streak == 1 ? "day" : "days"
            body = "I'm on a \(streak)-\(unit) gratitude streak on OpenThanks — living a more grateful life."
        } else {
            body = "Starting my gratitude journey on OpenThanks — living a more grateful life."
        }
        return """
        \(body)

        Get OpenThanks: \(inviteURL.absoluteString)
        """
    }

    var linkMetadataTitle: String {
        streak > 0 ? "My \(streak)-day OpenThanks streak" : "My OpenThanks gratitude journey"
    }
}

/// Portrait pride card (1080×1350) for Stories / Messages / IG.
struct StatsShareCardView: View {
    let content: StatsShareContent
    var avatar: UIImage? = nil

    private let coral = Color(hex: 0xE07A5F)
    private let width: CGFloat = 1080
    private let height: CGFloat = 1350

    var body: some View {
        ZStack {
            posterBackground

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(coral)
                    Text("OpenThanks")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    if let avatar {
                        Image(uiImage: avatar)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
                    }
                }
                .padding(.top, 72)

                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Text(content.streak > 0 ? "\(content.streak)" : "—")
                        .font(.system(size: 180, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    Text(content.streak > 0 ? "day streak" : "Starting my gratitude journey")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }

                Spacer(minLength: 28)

                VStack(spacing: 14) {
                    if content.bestStreak > 0 {
                        Text("Best streak: \(content.bestStreak) days")
                            .font(.system(size: 28, weight: .medium, design: .rounded))
                            .foregroundStyle(coral.opacity(0.95))
                    }
                    if content.sentCount > 0 {
                        let acceptedLine = content.acceptedCount > 0
                            ? "\(content.sentCount) sent · \(content.acceptedCount) accepted"
                            : "\(content.sentCount) appreciations sent"
                        Text(acceptedLine)
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text("Living a more grateful life")
                        .font(.system(size: 30, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(.white.opacity(0.78))
                        .padding(.top, 8)
                }

                Spacer(minLength: 36)

                appStoreFooter
                    .padding(.bottom, 64)
            }
            .padding(.horizontal, 64)
        }
        .frame(width: width, height: height)
        .clipped()
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
                .frame(width: 640, height: 640)
                .blur(radius: 70)
                .offset(x: 220, y: 420)

            Circle()
                .fill(Color.white.opacity(0.05))
                .frame(width: 480, height: 480)
                .blur(radius: 40)
                .offset(x: -260, y: -380)
        }
    }

    private var appStoreFooter: some View {
        HStack(spacing: 18) {
            OpenThanksAppIconMark(size: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text("Get OpenThanks")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.15, green: 0.12, blue: 0.11))
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.26))
                    Text("App Store · \(content.displayInviteLink)")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.35, green: 0.28, blue: 0.26))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(coral)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
        )
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .frame(maxWidth: .infinity)
    }
}

/// Primary OpenThanks app icon for the pride-card footer (not the blue App Store “A”).
private struct OpenThanksAppIconMark: View {
    var size: CGFloat = 56

    /// Prefer the 1024px Default asset so ImageRenderer stays sharp at 1080-wide.
    private var icon: UIImage {
        UIImage(named: "AppIcon-Default")
            ?? AppIconOption.default.previewImage
    }

    var body: some View {
        Image(uiImage: icon)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            .accessibilityLabel("OpenThanks")
    }
}

enum StatsShareRenderer {
    @MainActor
    static func prideImage(for content: StatsShareContent, avatar: UIImage? = nil) -> UIImage? {
        let view = StatsShareCardView(content: content, avatar: avatar)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        if let image = renderer.uiImage { return image }
        renderer.proposedSize = ProposedViewSize(width: 1080, height: 1350)
        return renderer.uiImage
    }

    @MainActor
    static func prideImage(for content: StatsShareContent, avatarURL: URL?) async -> UIImage? {
        var avatar: UIImage?
        if let avatarURL {
            avatar = await RemoteImageCache.load(avatarURL, maxPixelSize: 240)
        }
        if let image = prideImage(for: content, avatar: avatar) { return image }
        await Task.yield()
        return prideImage(for: content, avatar: avatar)
    }
}
