import SwiftUI

/// Presents Universal Link destinations as a full-screen cover.
/// Pass `auth` explicitly — `@Environment(AuthService.self)` on a modifier
/// applied outside `.environment(auth)` crashes at launch.
struct DeepLinkHostModifier: ViewModifier {
    @Bindable var deepLinks: DeepLinkRouter
    var auth: AuthService

    private var showPayItForward: Binding<Bool> {
        Binding(
            get: { deepLinks.payItForwardFromName != nil },
            set: { if !$0 { deepLinks.payItForwardFromName = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $deepLinks.destination) { destination in
                destinationView(destination)
                    .environment(auth)
                    .environment(deepLinks)
                    .syncAppAppearance()
                    .sheet(isPresented: showPayItForward) {
                        PayItForwardSheet(
                            fromName: deepLinks.payItForwardFromName,
                            onThankSomeone: {
                                Analytics.capture(
                                    "pay_it_forward_tapped",
                                    ["source": "claim_accept"]
                                )
                                deepLinks.payItForwardFromName = nil
                                deepLinks.clear()
                                ComposeLaunchBridge.shared.queue(
                                    analyticsSource: "post_accept_pay_it_forward"
                                )
                            }
                        )
                        .syncAppAppearance()
                    }
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
        case .pendingSent(let resendId):
            NavigationStack {
                PendingAppreciationsView(highlightId: resendId)
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
    func deepLinkHost(_ deepLinks: DeepLinkRouter, auth: AuthService) -> some View {
        modifier(DeepLinkHostModifier(deepLinks: deepLinks, auth: auth))
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
