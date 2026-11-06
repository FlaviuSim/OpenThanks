import Foundation

/// Home campaign card built only from the remote feed and `app_config`.
///
/// The card is one Send control. Tapping the ask and tapping the remote CTA
/// are the same action, so both record `campaign_prompt_tapped`. There is no
/// local campaign sentence and no local button label.
struct CampaignPromptCardContent: Equatable, Sendable {
    var eyebrow: String?
    var theme: String?
    var ask: String
    /// Remote CTA. Nil when the feed and `app_config` omitted it — the ask is the button.
    var buttonTitle: String?
    var progress: String?

    var accessibilityLabel: String {
        [ask, buttonTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

enum CampaignPromptTap: Equatable {
    /// The only control on the home campaign card.
    case send
}

enum CampaignPromptCardModel {
    /// PostHog event for `CampaignPromptTap.send`.
    static let tapEvent = "campaign_prompt_tapped"

    /// JSON key on the campaign feed, a prompt, and `app_config.competition`.
    static let ctaKey = "cta"

    static func recordsTap(_ action: CampaignPromptTap) -> Bool {
        switch action {
        case .send:
            return true
        }
    }

    /// Empty and whitespace-only remote labels are omitted. Never replaced locally.
    static func normalizeLabel(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Prompt CTA, then feed CTA, then `app_config`. First non-empty wins.
    static func buttonTitle(promptCTA: String?, feedCTA: String?, configCTA: String?) -> String? {
        for candidate in [promptCTA, feedCTA, configCTA] {
            if let label = normalizeLabel(candidate) {
                return label
            }
        }
        return nil
    }

    /// Nil when the remote ask is empty, so the card is not shown with local copy.
    static func content(
        feedTitle: String?,
        day: Int,
        theme: String?,
        prompt: String,
        promptCTA: String?,
        feedCTA: String?,
        configCTA: String?,
        daysSent: Int?,
        totalDays: Int
    ) -> CampaignPromptCardContent? {
        guard let ask = normalizeLabel(prompt) else { return nil }
        let title = normalizeLabel(feedTitle)
        let themeLine = normalizeLabel(theme).flatMap { line in
            line.caseInsensitiveCompare(ask) == .orderedSame ? nil : line
        }
        let progress = daysSent.map { "\($0) of \(totalDays) days" }
        return CampaignPromptCardContent(
            eyebrow: title.map { "\($0) · Day \(day)" },
            theme: themeLine,
            ask: ask,
            buttonTitle: buttonTitle(promptCTA: promptCTA, feedCTA: feedCTA, configCTA: configCTA),
            progress: progress
        )
    }
}
