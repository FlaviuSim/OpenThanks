import SwiftUI
import UIKit

/// Stories-style appreciation card for feed, compose preview, detail, and share export.
struct AppreciationCardView: View {
    let message: String
    var style: AppreciationCardStyle
    var mediaURL: URL? = nil
    /// Local photo for compose preview / share export (preferred over AsyncImage when set).
    var mediaImage: UIImage? = nil
    var mediaType: String? = nil
    var authorName: String? = nil
    var recipientName: String? = nil
    var exportSize: CGSize? = nil

    private var hasMedia: Bool { mediaImage != nil || mediaURL != nil }

    private var effectiveStyle: AppreciationCardStyle {
        if hasMedia {
            var s = style
            s.backgroundId = .custom_media
            return s
        }
        if style.backgroundId == .custom_media {
            var s = style
            s.backgroundId = .sunrise
            return s
        }
        return style
    }

    private var lightText: Bool {
        effectiveStyle.backgroundId == .custom_media || effectiveStyle.usesLightText
    }

    private var isVideo: Bool {
        mediaType?.lowercased().hasPrefix("video") == true
    }

    var body: some View {
        GeometryReader { geo in
            let w = exportSize?.width ?? geo.size.width
            let h = exportSize?.height ?? geo.size.height
            let pad = w * 0.07
            let fontSize = max(18, min(w * 0.055, 44))

            ZStack(alignment: .bottom) {
                backgroundLayer(width: w, height: h)

                VStack(alignment: effectiveStyle.textAlign == .left ? .leading : .center, spacing: 12) {
                    Text(AppreciationCardPresets.snippet(message).isEmpty
                         ? "Your appreciation…"
                         : AppreciationCardPresets.snippet(message))
                        .font(AppreciationCardPresets.font(for: effectiveStyle.typePreset, size: fontSize))
                        .foregroundStyle(lightText ? Color.white : Color(hex: 0x2D2A26))
                        .shadow(color: lightText ? .black.opacity(0.35) : .clear, radius: 8, y: 2)
                        .multilineTextAlignment(effectiveStyle.textAlign == .left ? .leading : .center)
                        .frame(maxWidth: .infinity, alignment: effectiveStyle.textAlign == .left ? .leading : .center)

                    if let authorName, let recipientName {
                        Text("\(authorName) → \(recipientName)")
                            .font(Theme.body(max(11, fontSize * 0.4), weight: .medium))
                            .foregroundStyle(lightText ? Color.white.opacity(0.9) : Color(hex: 0x2D2A26).opacity(0.85))
                    }

                    Text("OPENTHANKS")
                        .font(Theme.body(max(9, fontSize * 0.28), weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(lightText ? Color.white.opacity(0.7) : Color(hex: 0x2D2A26).opacity(0.55))
                }
                .padding(pad)
                .padding(.bottom, pad * 0.5)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: exportSize == nil ? 20 : 0, style: .continuous))
        }
        .aspectRatio(exportSize == nil ? (9 / 16) : nil, contentMode: .fit)
    }

    @ViewBuilder
    private func backgroundLayer(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            AppreciationCardPresets.gradient(for: effectiveStyle.backgroundId)
                .frame(width: width, height: height)

            if effectiveStyle.backgroundId == .custom_media, hasMedia {
                if let mediaImage {
                    Image(uiImage: mediaImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width, height: height)
                        .clipped()
                } else if let mediaURL {
                    if isVideo {
                        // Poster-style: show as dark fill; feed uses FlexiblePostMedia elsewhere when needed.
                        Color.black.opacity(0.3)
                        AsyncImage(url: mediaURL) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            }
                        }
                        .frame(width: width, height: height)
                        .clipped()
                    } else {
                        AsyncImage(url: mediaURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Color.black.opacity(0.2)
                            }
                        }
                        .frame(width: width, height: height)
                        .clipped()
                    }
                }
                LinearGradient(
                    colors: [.clear, .black.opacity(0.25), .black.opacity(0.75)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}
