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
                                var props: [String: Any] = ["source": "claim_accept"]
                                if let parentId = deepLinks.payItForwardParentId {
                                    props["parent_gratitude_id"] = parentId.uuidString.lowercased()
                                }
                                Analytics.capture("pay_it_forward_tapped", props)
                                let parentId = deepLinks.payItForwardParentId
                                let fromName = deepLinks.payItForwardFromName
                                deepLinks.payItForwardFromName = nil
                                deepLinks.payItForwardParentId = nil
                                deepLinks.clear()
                                ComposeLaunchBridge.shared.queue(
                                    inspiredByGratitudeId: parentId,
                                    inspiredByAuthorName: fromName,
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
        case .profile(let username, let tab):
            NavigationStack {
                ProfileUsernameLoaderView(username: username, initialSection: tab?.profileSection)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { deepLinks.clear() }
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .appDestinations()
            }
        case .profileId(let id, let tab):
            NavigationStack {
                ProfileIdLoaderView(profileId: id, initialSection: tab?.profileSection)
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
    var initialSection: UserProfileView.Section? = nil
    @State private var profile: Profile?
    @State private var failed = false

    var body: some View {
        Group {
            if let profile {
                UserProfileView(profile: profile, initialSection: initialSection)
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

struct ProfileIdLoaderView: View {
    let profileId: UUID
    var initialSection: UserProfileView.Section? = nil
    @State private var profile: Profile?
    @State private var failed = false

    var body: some View {
        Group {
            if let profile {
                UserProfileView(profile: profile, initialSection: initialSection)
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
            do { profile = try await GratitudeService.profile(id: profileId) }
            catch {
                if !error.isCancellation { failed = true }
            }
        }
    }
}
