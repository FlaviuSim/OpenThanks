import SwiftUI

/// One-time signed-in intro after permissions/profile: what OpenThanks is (not spam).
struct TrustIntroView: View {
    var onFinished: () -> Void

    private struct Point: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
    }

    private let points: [Point] = [
        .init(
            id: "real",
            icon: "heart.fill",
            title: "Real thank-yous",
            body: "OpenThanks is for genuine appreciation between people — not ads, marketing, or spam."
        ),
        .init(
            id: "accept",
            icon: "checkmark.shield.fill",
            title: "You choose what to accept",
            body: "Nothing posts publicly until the recipient reviews and accepts. Decline anytime."
        ),
        .init(
            id: "send",
            icon: "paperplane.fill",
            title: "Pass kindness forward",
            body: "When you’re ready, tap the heart button to thank someone who made your day better."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        ActionGlyph(systemImage: "heart.fill", size: 72)
                            .softNoteReveal(delay: 0.02)

                        VStack(spacing: 8) {
                            Text("This is real gratitude")
                                .font(Theme.display(28, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("A simple place for thank-you notes — built on trust.")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .softNoteReveal(delay: 0.06)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                            pointRow(point)
                                .softNoteReveal(delay: 0.1 + Double(index) * 0.05)
                            if index < points.count - 1 {
                                Rectangle()
                                    .fill(Theme.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 62)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                    .softNoteReveal(delay: 0.12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                Button("Continue to Home") {
                    Analytics.capture("trust_intro_completed", ["action": "continue"])
                    onFinished()
                }
                .buttonStyle(CTAButtonStyle())

                Button("Skip") {
                    Analytics.capture("trust_intro_completed", ["action": "skip"])
                    onFinished()
                }
                .font(Theme.body(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .syncAppAppearance()
        .readableWidth()
        .onAppear {
            Analytics.capture("trust_intro_shown")
        }
    }

    private func pointRow(_ point: Point) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: point.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 40, height: 40)
                .background(Theme.coral.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(point.body)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}
