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

    private let points: [Point] = [
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
            body: "Recipients review every note first. Nothing posts until they say yes."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                slideContent
                    .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Being thanked")
                    .font(Theme.display(36, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("changes everything")
                    .font(Theme.display(36, weight: .semibold))
                    .foregroundStyle(Theme.heartGradient)
            }
            .padding(.top, 16)
            .softNoteReveal(delay: 0.02)

            Text("A sincere note can make someone’s whole day — and they feel it the moment they open it.")
                .font(Theme.body(16))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .softNoteReveal(delay: 0.06)

            VStack(alignment: .leading, spacing: 18) {
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
                    .softNoteReveal(delay: 0.1 + Double(pointIndex) * 0.05)
                }
            }

            ReceiveMomentPreview()
                .softNoteReveal(delay: 0.22)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }
}

/// Composed preview of receiving an appreciation — the emotional hook for Get Started.
private struct ReceiveMomentPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 28, height: 28)
                    .background(Theme.coral.opacity(0.16), in: Circle())
                Text("You received thanks")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("From Alex")
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.3)

                Text("Thank you for jumping in when I was stuck. You made a hard week feel lighter.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label("Accept", systemImage: "checkmark")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x2B1209))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.ctaGradient, in: Capsule())

                    Text("You choose what becomes public")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.coral.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.coral.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview of receiving a thank-you note you can accept before it’s public")
    }
}
