import SwiftUI

/// Soft Home banner when the App Store has a newer OpenThanks than this install.
struct AppUpdateBanner: View {
    var storeVersion: String?
    var onUpdate: () -> Void
    var onLater: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ActionGlyph(systemImage: "arrow.down.app.fill", size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("A newer OpenThanks is ready")
                    .font(Theme.body(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Button("Update", action: onUpdate)
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

    private var subtitle: String {
        if let storeVersion, !storeVersion.isEmpty {
            return "Version \(storeVersion) is on the App Store — update when you have a moment."
        }
        return "Update when you have a moment for the latest improvements."
    }
}
