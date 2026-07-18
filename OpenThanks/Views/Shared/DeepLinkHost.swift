import SwiftUI

/// Presents Universal Link destinations as a full-screen cover once the user
/// is signed in (claim links require an account).
struct DeepLinkHostModifier: ViewModifier {
    @Bindable var deepLinks: DeepLinkRouter
    @Environment(AuthService.self) private var auth

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $deepLinks.destination) { destination in
                destinationView(destination)
                    .environment(auth)
                    .syncAppAppearance()
            }
    }

    @ViewBuilder
    private func destinationView(_ destination: DeepLinkRouter.Destination) -> some View {
        switch destination {
        case .claim(let token):
            ClaimAppreciationView(token: token)
        case .gratitude(let id):
            NavigationStack {
                GratitudeLoaderView(gratitudeId: id)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { deepLinks.clear() }
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .appDestinations()
            }
        case .slug(let slug):
            NavigationStack {
                GratitudeSlugLoaderView(slug: slug)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { deepLinks.clear() }
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .appDestinations()
            }
        case .profile(let username):
            NavigationStack {
                ProfileUsernameLoaderView(username: username)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { deepLinks.clear() }
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .appDestinations()
            }
        }
    }
}

extension View {
    func deepLinkHost(_ deepLinks: DeepLinkRouter) -> some View {
        modifier(DeepLinkHostModifier(deepLinks: deepLinks))
    }
}

struct GratitudeSlugLoaderView: View {
    let slug: String
    @State private var gratitude: Gratitude?
    @State private var failed = false

    var body: some View {
        Group {
            if let gratitude {
                GratitudeDetailView(gratitude: gratitude)
            } else if failed {
                unavailable
            } else {
                ProgressView().tint(Theme.coral)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            do { gratitude = try await GratitudeService.gratitude(slug: slug) }
            catch {
                if !error.isCancellation { failed = true }
            }
        }
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            HeartMark(size: 40)
            Text("This appreciation isn't available.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}

struct ProfileUsernameLoaderView: View {
    let username: String
    @State private var profile: Profile?
    @State private var failed = false

    var body: some View {
        Group {
            if let profile {
                UserProfileView(profile: profile)
            } else if failed {
                VStack(spacing: 10) {
                    HeartMark(size: 40)
                    Text("Profile not found.")
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
            do { profile = try await GratitudeService.profile(username: username) }
            catch {
                if !error.isCancellation { failed = true }
            }
        }
    }
}
