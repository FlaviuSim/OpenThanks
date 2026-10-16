import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var didTrackWelcomePage = false

    private struct Point: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
    }

    private let headline = ["Feel happier", "through", "gratitude"]
    private let points: [Point] = [
        .init(
            id: "happier",
            icon: "sun.max.fill",
            title: "A more grateful life",
            body: "Noticing the people who matter — and thanking them — is one of the simplest ways to feel more fulfilled."
        ),
        .init(
            id: "send",
            icon: "paperplane.fill",
            title: "Send a real thank-you in seconds",
            body: "A name and a few honest words. That’s the whole product."
        ),
        .init(
            id: "trust",
            icon: "checkmark.shield.fill",
            title: "They accept before anything is public",
            body: "Recipients review every note first. This isn’t marketing or spam — it’s real gratitude."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            slideContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button("Get Started") {
                WarmHaptics.selection()
                // Existing funnel event for Get Started. Name kept for current insights.
                Analytics.capture("prelogin_onboarding_completed")
                onFinish()
            }
            .buttonStyle(CTAButtonStyle())
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            .accessibilityLabel("Get Started")
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .readableWidth()
        .onAppear {
            guard !didTrackWelcomePage else { return }
            didTrackWelcomePage = true
            Analytics.welcomePageViewed()
        }
    }

    private var slideContent: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(headline.indices, id: \.self) { i in
                    Text(headline[i])
                        .font(Theme.display(40, weight: .semibold))
                        .foregroundStyle(i == headline.count - 1
                                         ? AnyShapeStyle(Theme.heartGradient)
                                         : AnyShapeStyle(Theme.textPrimary))
                }
            }
            .padding(.top, 24)
            .softNoteReveal(delay: 0.02)

            VStack(alignment: .leading, spacing: 22) {
                ForEach(Array(points.enumerated()), id: \.element.id) { pointIndex, point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.coralLight)
                            .frame(width: 40, height: 40)
                            .background(Theme.surfaceRaised, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title)
                                .font(Theme.body(16, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(point.body)
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .softNoteReveal(delay: 0.08 + Double(pointIndex) * 0.06)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}
