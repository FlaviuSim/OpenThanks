import SwiftUI

/// Why a guest is being asked to sign in (action-gated, not a hard wall).
enum GuestSignInReason: String {
    case send, heart, myFeed, claim, browse

    var headline: String {
        switch self {
        case .send: "Sign in to send"
        case .heart: "Sign in to heart"
        case .myFeed: "Sign in for My Feed"
        case .claim: "Sign in to keep this"
        case .browse: "Sign in"
        }
    }

    var message: String {
        switch self {
        case .send:
            "Create a free account to send a thank-you. You can keep browsing without one."
        case .heart:
            "Sign in to heart appreciations. Browsing stays free."
        case .myFeed:
            "My Feed is your circle — sign in to see it. World Feed stays open."
        case .claim:
            "Sign in to keep or decline this thank-you."
        case .browse:
            "Sign in when you’re ready to send or keep a thank-you."
        }
    }
}

/// Lets pushed screens (post detail, etc.) request the same guest sign-in sheet
/// as Home, without each view inventing its own host.
private struct GuestSignInRequestKey: EnvironmentKey {
    static let defaultValue: ((GuestSignInReason) -> Void)? = nil
}

extension EnvironmentValues {
    var requestGuestSignIn: ((GuestSignInReason) -> Void)? {
        get { self[GuestSignInRequestKey.self] }
        set { self[GuestSignInRequestKey.self] = newValue }
    }
}

/// Signed-out Home: browse the public World feed and search people.
/// Sign-in is only required to send, heart, claim/accept, or open My Feed.
struct GuestBrowseShell: View {
    @State private var path = NavigationPath()
    @State private var searchActive = false
    @State private var chromeCollapsed = false
    @State private var showSignIn = false
    @State private var signInReason: GuestSignInReason = .browse

    var body: some View {
        ZStack(alignment: .bottom) {
            FeedView(
                path: $path,
                isSelected: true,
                searchActive: $searchActive,
                chromeCollapsed: $chromeCollapsed,
                isGuestMode: true,
                onRequestSignIn: { reason in
                    presentSignIn(reason: reason)
                }
            )
            .environment(\.requestGuestSignIn) { reason in
                presentSignIn(reason: reason)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !searchActive && !chromeCollapsed {
                guestChrome
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea(.keyboard)
        .animation(.easeInOut(duration: 0.2), value: searchActive)
        .animation(.easeInOut(duration: 0.2), value: chromeCollapsed)
        .sheet(isPresented: $showSignIn) {
            WelcomeView(
                headline: signInReason.headline,
                message: signInReason.message,
                showsCloseButton: true
            )
            .syncAppAppearance()
            .presentationDetents([.large])
        }
    }

    private var guestChrome: some View {
        HStack(spacing: 14) {
            Button {
                presentSignIn(reason: .browse)
            } label: {
                Text("Sign in")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.textSecondary.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sign in")

            Spacer(minLength: 0)

            Button {
                presentSignIn(reason: .send)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 58, height: 58)
                    .background(Theme.ctaGradient, in: Circle())
                    .shadow(color: Theme.coral.opacity(0.35), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thank Someone")
        }
        .padding(.horizontal, 20)
    }

    private func presentSignIn(reason: GuestSignInReason) {
        signInReason = reason
        showSignIn = true
        Analytics.capture("guest_sign_in_prompted", ["reason": reason.rawValue])
    }
}
