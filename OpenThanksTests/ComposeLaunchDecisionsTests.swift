import XCTest
#if canImport(LaunchDecisions)
@testable import LaunchDecisions
#endif
#if canImport(WidgetRouting)
@testable import WidgetRouting
#endif
#if canImport(OpenThanks)
@testable import OpenThanks
#endif

/// Launch stays on Home. Notification taps and compose deep links still open compose.
final class ComposeLaunchDecisionsTests: XCTestCase {
    func testReturningUserLaunchDoesNotAutoPresentCompose() {
        XCTAssertFalse(
            ComposeLaunchDecisions.shouldPresent(isAutomaticBlankLaunch: true),
            "cold start and foreground must not present a blank compose"
        )
        XCTAssertTrue(ComposeLaunchDecisions.isAutomaticBlankLaunch(
            analyticsSource: "app_open",
            hasRecipient: false,
            hasMessage: false,
            hasPlaceholder: false,
            hasProfile: false,
            hasImage: false,
            hasInspiredBy: false,
            hasCampaignHint: false,
            hasCampaignId: false,
            isEditing: false
        ))
        XCTAssertTrue(ComposeLaunchDecisions.isAutomaticBlankLaunch(
            analyticsSource: "post_login",
            hasRecipient: false,
            hasMessage: false,
            hasPlaceholder: false,
            hasProfile: false,
            hasImage: false,
            hasInspiredBy: false,
            hasCampaignHint: false,
            hasCampaignId: false,
            isEditing: false
        ))
        XCTAssertEqual(
            ComposeLaunchDecisions.automaticLaunchSources,
            ["app_open", "post_login"]
        )
    }

    func testExplicitComposeSourcesStillPresent() {
        let sources = [
            "notification_friday",
            "notification_campaign",
            "notification_thank_reminder",
            "notification_friday_tap",
            "deep_link_compose",
            "universal_link_compose",
            "campaign_deeplink",
            "campaign_universal_link",
            "control_center",
            "tab_compose",
            "draft_reminder",
            "siri_open_compose",
            "share_extension",
            "watch",
        ]
        for source in sources {
            XCTAssertFalse(
                ComposeLaunchDecisions.isAutomaticBlankLaunch(
                    analyticsSource: source,
                    hasRecipient: false,
                    hasMessage: false,
                    hasPlaceholder: false,
                    hasProfile: false,
                    hasImage: false,
                    hasInspiredBy: false,
                    hasCampaignHint: false,
                    hasCampaignId: false,
                    isEditing: false
                ),
                source
            )
            XCTAssertTrue(
                ComposeLaunchDecisions.shouldPresent(isAutomaticBlankLaunch: false),
                source
            )
        }
        XCTAssertFalse(ComposeLaunchDecisions.isAutomaticBlankLaunch(
            analyticsSource: "app_open",
            hasRecipient: true,
            hasMessage: false,
            hasPlaceholder: false,
            hasProfile: false,
            hasImage: false,
            hasInspiredBy: false,
            hasCampaignHint: false,
            hasCampaignId: false,
            isEditing: false
        ))
    }

    func testFridayAndThankReminderNotificationsStillOpenCompose() {
        XCTAssertEqual(
            ComposeLaunchDecisions.notificationRoute(type: "gratitude_friday", hasCampaignPrompt: false),
            .openCompose(analyticsSource: "notification_friday")
        )
        XCTAssertEqual(
            ComposeLaunchDecisions.notificationRoute(type: "gratitude_friday", hasCampaignPrompt: true),
            .openCompose(analyticsSource: "notification_campaign")
        )
        XCTAssertEqual(
            ComposeLaunchDecisions.notificationRoute(type: "thank_reminder", hasCampaignPrompt: false),
            .openCompose(analyticsSource: "notification_thank_reminder")
        )
        XCTAssertEqual(
            ComposeLaunchDecisions.notificationRoute(type: "gratitude_received", hasCampaignPrompt: false),
            .leaveComposeClosed
        )
        XCTAssertEqual(
            ComposeLaunchDecisions.notificationRoute(type: "gratitude_pending", hasCampaignPrompt: false),
            .leaveComposeClosed
        )
    }

    func testComposeDeepLinksStillOpenCompose() {
        let blank = URL(string: "https://openthanks.com/gratitude/new")!
        XCTAssertEqual(
            ComposeLaunchDecisions.universalLinkRoute(blank),
            .openCompose(analyticsSource: "universal_link_compose", recipientName: nil)
        )

        let prefilled = URL(string: "https://www.openthanks.com/gratitude/new?for=Ada%20Lovelace&source=friday_email")!
        XCTAssertEqual(
            ComposeLaunchDecisions.universalLinkRoute(prefilled),
            .openCompose(analyticsSource: "friday_email", recipientName: "Ada Lovelace")
        )

        let home = URL(string: "https://openthanks.com/feed")!
        XCTAssertEqual(ComposeLaunchDecisions.universalLinkRoute(home), .leaveComposeClosed)

        let detail = URL(string: "https://openthanks.com/gratitude/11111111-1111-1111-1111-111111111111")!
        XCTAssertEqual(ComposeLaunchDecisions.universalLinkRoute(detail), .leaveComposeClosed)

        XCTAssertTrue(ComposeLaunchDecisions.isCampaignComposeURL(
            URL(string: "https://openthanks.com/november")!
        ))
        XCTAssertFalse(ComposeLaunchDecisions.isCampaignComposeURL(
            URL(string: "https://openthanks.com/feed")!
        ))

        XCTAssertEqual(
            WidgetDeepLink.parse(URL(string: "openthanks://compose")!),
            .compose(nil)
        )
        XCTAssertEqual(
            WidgetDeepLink.parse(URL(string: "openthanks://compose?campaign=november-2026&day=3")!),
            .compose(CampaignComposeLink(id: "november-2026", day: 3))
        )
        XCTAssertEqual(WidgetDeepLink.parse(URL(string: "openthanks://home")!), .home)
        XCTAssertEqual(
            ComposeLaunchDecisions.customSchemeComposeRoute(fromControlCenter: false),
            .openCompose(analyticsSource: "deep_link_compose", recipientName: nil)
        )
        XCTAssertEqual(
            ComposeLaunchDecisions.customSchemeComposeRoute(fromControlCenter: true),
            .openCompose(analyticsSource: "control_center", recipientName: nil)
        )
    }
}
