import SwiftUI

/// Subtle Home card for the active day's campaign prompt.
struct CampaignPromptCard: View {
    var day: Int
    var theme: String?
    var prompt: String
    var daysSent: Int?
    var totalDays: Int
    var onThank: () -> Void

    private var themeLine: String? {
        let trimmed = theme?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.caseInsensitiveCompare(prompt) != .orderedSame else { return nil }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(CampaignFeed.cardTitle) · Day \(day)")
                .font(Theme.body(12, weight: .semibold))
                .foregroundStyle(Theme.coral)

            if let themeLine {
                Text(themeLine)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(prompt)
                .font(Theme.body(15))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 12) {
                if let daysSent {
                    Text("\(daysSent) of \(totalDays) days")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Button(action: onThank) {
                    Text("Thank someone")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x2B1209))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.ctaGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Thank someone")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
