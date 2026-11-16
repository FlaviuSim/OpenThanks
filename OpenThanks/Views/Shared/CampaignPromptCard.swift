import SwiftUI

/// Compact home strip for the day's campaign ask. Copy and the button label come
/// from the remote feed / `app_config`. The whole card is the one Send control, so
/// a tap on the ask records `campaign_prompt_tapped`.
struct CampaignPromptCard: View {
    var content: CampaignPromptCardContent
    var onSend: () -> Void

    var body: some View {
        Button(action: onSend) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let eyebrow = content.eyebrow {
                        Text(eyebrow)
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundStyle(Theme.coral)
                            .lineLimit(1)
                    }

                    Text(content.ask)
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let buttonTitle = content.buttonTitle {
                    Text(buttonTitle)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x2B1209))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.ctaGradient, in: Capsule())
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .accessibilityLabel(content.accessibilityLabel)
    }
}
