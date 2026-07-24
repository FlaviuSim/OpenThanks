import AVKit
import SwiftUI

/// Renders an appreciation image or video with the same flexible sizing as photos.
struct FlexiblePostMedia: View {
    let url: URL
    var mediaType: String?
    var maxHeight: CGFloat = 480
    var cornerRadius: CGFloat = 14

    private var isVideo: Bool {
        mediaType?.lowercased().hasPrefix("video") == true
    }

    var body: some View {
        Group {
            if isVideo {
                PostVideoPlayer(url: url, maxHeight: maxHeight)
            } else {
                FlexiblePostImage(url: url, maxHeight: maxHeight, cornerRadius: cornerRadius)
            }
        }
    }
}

/// Inline video player for feed / detail / compose previews.
struct PostVideoPlayer: View {
    let url: URL
    var maxHeight: CGFloat = 420
    var cornerRadius: CGFloat = 14

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity)
            .frame(height: min(maxHeight, 360))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear { ensurePlayer() }
            .onChange(of: url) { _, _ in
                player?.pause()
                player = AVPlayer(url: url)
            }
            .onDisappear {
                player?.pause()
            }
            .accessibilityLabel("Video attachment")
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        player = AVPlayer(url: url)
    }
}

/// Full-screen video viewer (compose / feed tap).
struct FullScreenVideoView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

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
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
