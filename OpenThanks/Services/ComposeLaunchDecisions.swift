import Foundation

/// Whether compose should open by itself.
///
/// Cold start and return-to-foreground for a returning, signed-in user stay on
/// Home. Notification taps and compose deep links still open the sheet.
/// Tap-to-compose, Siri, share, pay-it-forward, and draft restore do not use this.
enum ComposeLaunchDecisions {
    /// Analytics sources that mean the app invented a blank appreciation
    /// because it launched or finished sign-in.
    static let automaticLaunchSources: Set<String> = ["app_open", "post_login"]

    /// Blank `app_open` / `post_login` requests. A prefilled field is not automatic.
    static func isAutomaticBlankLaunch(
        analyticsSource: String,
        hasRecipient: Bool,
        hasMessage: Bool,
        hasPlaceholder: Bool,
        hasProfile: Bool,
        hasImage: Bool,
        hasInspiredBy: Bool,
        hasCampaignHint: Bool,
        hasCampaignId: Bool,
        isEditing: Bool
    ) -> Bool {
        guard automaticLaunchSources.contains(analyticsSource) else { return false }
        return !hasRecipient
            && !hasMessage
            && !hasPlaceholder
            && !hasProfile
            && !hasImage
            && !hasInspiredBy
            && !hasCampaignHint
            && !hasCampaignId
            && !isEditing
    }

    /// Returning signed-in launch/foreground must not present an automatic blank compose.
    /// Explicit queued requests (notification, deep link, Siri, share, draft) still present.
    static func shouldPresent(isAutomaticBlankLaunch: Bool) -> Bool {
        !isAutomaticBlankLaunch
    }

    enum NotificationRoute: Equatable {
        case openCompose(analyticsSource: String)
        case leaveComposeClosed
    }

    /// Push / local notification taps. Friday (with or without a campaign prompt)
    /// and the named thank-reminder open compose. Other types keep their own destinations.
    static func notificationRoute(type: String, hasCampaignPrompt: Bool) -> NotificationRoute {
        switch type {
        case "gratitude_friday":
            return .openCompose(
                analyticsSource: hasCampaignPrompt ? "notification_campaign" : "notification_friday"
            )
        case "thank_reminder":
            return .openCompose(analyticsSource: "notification_thank_reminder")
        default:
            return .leaveComposeClosed
        }
    }

    enum DeepLinkRoute: Equatable {
        case openCompose(analyticsSource: String, recipientName: String?)
        case leaveComposeClosed
    }

    /// `https://openthanks.com/gratitude/new` (optional `for` and `source`).
    static func universalLinkRoute(_ url: URL) -> DeepLinkRoute {
        let parts = pathParts(url)
        guard parts.count >= 2,
              parts[0].lowercased() == "gratitude",
              parts[1].lowercased() == "new"
        else { return .leaveComposeClosed }
        let source = query(url, "source")
        let recipient = query(url, "for")
        return .openCompose(
            analyticsSource: (source?.isEmpty == false) ? source! : "universal_link_compose",
            recipientName: (recipient?.isEmpty == false) ? recipient : nil
        )
    }

    /// `openthanks://compose` with no campaign query, or a Control Center handoff.
    static func customSchemeComposeRoute(fromControlCenter: Bool) -> DeepLinkRoute {
        .openCompose(
            analyticsSource: fromControlCenter ? "control_center" : "deep_link_compose",
            recipientName: nil
        )
    }

    /// `https://openthanks.com/november` opens campaign compose.
    static func isCampaignComposeURL(_ url: URL) -> Bool {
        pathParts(url).first?.lowercased() == "november"
    }

    private static func pathParts(_ url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" }
            .map { $0.removingPercentEncoding ?? $0 }
    }

    private static func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
