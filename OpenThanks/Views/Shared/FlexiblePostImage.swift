import SwiftUI

/// Post photo that keeps the source aspect ratio (tall or wide) within a max height.
struct FlexiblePostImage: View {
    let url: URL
    var maxHeight: CGFloat = 480
    var cornerRadius: CGFloat = 14

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: maxHeight)
            case .failure:
                placeholder
            case .empty:
                ProgressView().tint(Theme.coral)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(Theme.surfaceRaised)
            @unknown default:
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Theme.surfaceRaised)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
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
