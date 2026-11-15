import SwiftUI

/// Home card for the day's campaign ask. Copy and the button label come from
/// the remote feed / `app_config`. The whole card is the one Send control, so
/// a tap on the ask records `campaign_prompt_tapped`.
struct CampaignPromptCard: View {
    var content: CampaignPromptCardContent
    var onSend: () -> Void

    var body: some View {
        Button(action: onSend) {
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow = content.eyebrow {
                    Text(eyebrow)
                        .font(Theme.body(12, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }

                if let theme = content.theme {
                    Text(theme)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textTertiary)
                }

                Text(content.ask)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)

                HStack(alignment: .center, spacing: 12) {
                    if let progress = content.progress {
                        Text(progress)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if let buttonTitle = content.buttonTitle {
                        Text(buttonTitle)
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x2B1209))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.ctaGradient, in: Capsule())
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        )
        .accessibilityLabel(content.accessibilityLabel)
    }
}
