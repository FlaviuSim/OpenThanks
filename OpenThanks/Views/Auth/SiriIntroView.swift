import SwiftUI
import AppIntents

/// Post-login tip (shown on the second app open): every way to start an appreciation.
struct SiriIntroView: View {
    var onFinished: () -> Void

    private struct ShareWay: Identifiable {
        let id: String
        let icon: String
        let title: String
        let body: String
    }

    private let ways: [ShareWay] = [
        .init(
            id: "app",
            icon: "plus.circle.fill",
            title: "In the app",
            body: "Tap the + button anytime to write and send a thank-you."
        ),
        .init(
            id: "watch",
            icon: "applewatch",
            title: "On Apple Watch",
            body: "Dictate or type a quick appreciation from your wrist."
        ),
        .init(
            id: "siri",
            icon: "waveform",
            title: "With Siri",
            body: "Say “Send an appreciation on OpenThanks” or “Thank Maria on OpenThanks.”"
        ),
        .init(
            id: "widget",
            icon: "rectangle.grid.2x2.fill",
            title: "Home Screen widget",
            body: "Add the OpenThanks widget for a one-tap jump into compose."
        ),
        .init(
            id: "photos",
            icon: "square.and.arrow.up",
            title: "From Photos",
            body: "Open a photo → Share → OpenThanks to attach it to an appreciation."
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 14) {
                        ActionGlyph(systemImage: "paperplane.fill", size: 72)
                            .softNoteReveal(delay: 0.02)

                        VStack(spacing: 8) {
                            Text("Say thanks your way")
                                .font(Theme.display(28, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("OpenThanks meets you wherever the moment is — app, Watch, Siri, widget, or a photo you already have.")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .softNoteReveal(delay: 0.06)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 0) {
                        ForEach(Array(ways.enumerated()), id: \.element.id) { index, way in
                            shareWayRow(way)
                                .softNoteReveal(delay: 0.1 + Double(index) * 0.05)
                            if index < ways.count - 1 {
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
                Button("Got it", action: onFinished)
                    .buttonStyle(CTAButtonStyle())

                Text("You can explore these anytime — nothing else to set up.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
        .syncAppAppearance()
        .onAppear {
            OpenThanksShortcuts.updateAppShortcutParameters()
        }
    }

    private func shareWayRow(_ way: ShareWay) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: way.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 40, height: 40)
                .background(Theme.coral.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(way.title)
                    .font(Theme.body(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(way.body)
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
