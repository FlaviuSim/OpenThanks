import SwiftUI

/// Post photo that keeps the source aspect ratio (tall or wide) within a max height.
struct FlexiblePostImage: View {
    let url: URL
    var maxHeight: CGFloat = 480
    var cornerRadius: CGFloat = 14

    var body: some View {
        CachedAsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: maxHeight)
        } placeholder: {
            ProgressView().tint(Theme.coral)
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Theme.surfaceRaised)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    /// Local UIImage preview with flexible tall/wide sizing.
    func flexiblePhotoPreview(maxHeight: CGFloat = 420) -> some View {
        self
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: maxHeight)
    }
}
