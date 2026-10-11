import SwiftUI

/// Soft Home banner when calendar isn’t connected after onboarding.
struct CalendarConnectBanner: View {
    var onConnect: () -> Void
    var onLater: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ActionGlyph(systemImage: "calendar", size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("Turn on calendar for thank-you ideas")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("We’ll suggest one person from today’s meetings, weekday evenings at 8.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button("Connect", action: onConnect)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x2B1209))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.ctaGradient, in: Capsule())

                Button("Later", action: onLater)
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.coral.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
