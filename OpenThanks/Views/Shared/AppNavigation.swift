import SwiftUI

/// Route for posts we only know by id (e.g. notification taps).
struct GratitudeIdRoute: Hashable { let id: UUID }

extension View {
    /// Registers the app-wide push destinations. Apply once at the root of
    /// every NavigationStack so profiles and posts can be pushed from anywhere.
    func appDestinations() -> some View {
        self
            .navigationDestination(for: Profile.self) { UserProfileView(profile: $0) }
            .navigationDestination(for: Gratitude.self) { GratitudeDetailView(gratitude: $0) }
            .navigationDestination(for: GratitudeIdRoute.self) { GratitudeLoaderView(gratitudeId: $0.id) }
    }
}

/// An avatar that pushes the person's profile when tapped — used everywhere
/// a profile image appears.
struct ProfileAvatarLink: View {
    let profile: Profile?
    var size: CGFloat = 40

    var body: some View {
        if let profile {
            NavigationLink(value: profile) {
                AvatarView(profile: profile, size: size)
            }
            .buttonStyle(.plain)
        } else {
            AvatarView(profile: nil, size: size)
        }
    }
}

/// Loads a post by id, then shows the detail screen.
struct GratitudeLoaderView: View {
    let gratitudeId: UUID
    @State private var gratitude: Gratitude?
    @State private var failed = false

    var body: some View {
        Group {
            if let gratitude {
                GratitudeDetailView(gratitude: gratitude)
            } else if failed {
                VStack(spacing: 10) {
                    HeartMark(size: 40)
                    Text("This appreciation isn't available.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
            } else {
                ProgressView().tint(Theme.coral)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            do { gratitude = try await GratitudeService.gratitude(id: gratitudeId) }
            catch {
                if !error.isCancellation { failed = true }
            }
        }
    }
}

/// Full-screen, pinch-zoomable image viewer.
struct FullScreenImageView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification.simultaneously(with: drag))
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(duration: 0.3)) {
                            if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                        }
                    }
            } placeholder: {
                ProgressView().tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
    }

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = max(1, lastScale * value.magnification)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1.02 { withAnimation(.spring(duration: 0.3)) { reset() } }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1 {
                    offset = CGSize(width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height)
                } else {
                    offset = CGSize(width: 0, height: max(0, value.translation.height))
                }
            }
            .onEnded { value in
                if scale > 1 {
                    lastOffset = offset
                } else if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { offset = .zero }
                }
            }
    }

    private func reset() {
        scale = 1; lastScale = 1
        offset = .zero; lastOffset = .zero
    }
}
