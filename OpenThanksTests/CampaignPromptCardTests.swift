import XCTest
#if canImport(CampaignPrompt)
@testable import CampaignPrompt
#else
@testable import OpenThanks
#endif

final class CampaignPromptCardTests: XCTestCase {
    private let ask = "Thank a mentor who told you the truth and stayed in your corner afterward."

    func testTapEventFiresForTheSingleSendAction() {
        XCTAssertEqual(CampaignPromptCardModel.tapEvent, "campaign_prompt_tapped")
        XCTAssertTrue(CampaignPromptCardModel.recordsTap(.send))
    }

    func testCardUsesRemoteAskAndOmitsALocalButtonWhenCTAIsMissing() {
        let card = CampaignPromptCardModel.content(
            feedTitle: "30 Days of Thanks: Who Shaped You?",
            day: 5,
            theme: "A mentor",
            prompt: ask,
            promptCTA: nil,
            feedCTA: "  ",
            configCTA: nil,
            daysSent: 2,
            totalDays: 30
        )

        XCTAssertEqual(card?.ask, ask)
        XCTAssertEqual(card?.theme, "A mentor")
        XCTAssertEqual(card?.eyebrow, "30 Days of Thanks: Who Shaped You? · Day 5")
        XCTAssertEqual(card?.progress, "2 of 30 days")
        XCTAssertNil(card?.buttonTitle)
        let visible = [
            card?.eyebrow,
            card?.theme,
            card?.ask,
            card?.buttonTitle,
            card?.progress,
        ].compactMap { $0 }.joined(separator: "\n")
        XCTAssertFalse(visible.contains("Thank someone"))
        XCTAssertFalse(visible.localizedCaseInsensitiveContains("watch"))
    }

    func testButtonTitleComesFromPromptThenFeedThenAppConfig() {
        XCTAssertEqual(
            CampaignPromptCardModel.buttonTitle(
                promptCTA: " Send ",
                feedCTA: "Feed",
                configCTA: "Config"
            ),
            "Send"
        )
        XCTAssertEqual(
            CampaignPromptCardModel.buttonTitle(
                promptCTA: " ",
                feedCTA: "Send today's note",
                configCTA: "Config"
            ),
            "Send today's note"
        )
        XCTAssertEqual(
            CampaignPromptCardModel.buttonTitle(
                promptCTA: nil,
                feedCTA: nil,
                configCTA: "Send"
            ),
            "Send"
        )
        XCTAssertNil(
            CampaignPromptCardModel.buttonTitle(
                promptCTA: nil,
                feedCTA: "",
                configCTA: " \n "
            )
        )
    }

    func testMissingRemoteTitleIsNotReplacedWithLocalCampaignCopy() {
        let card = CampaignPromptCardModel.content(
            feedTitle: "  ",
            day: 5,
            theme: nil,
            prompt: ask,
            promptCTA: nil,
            feedCTA: nil,
            configCTA: "Send",
            daysSent: nil,
            totalDays: 30
        )
        XCTAssertNil(card?.eyebrow)
        XCTAssertNil(card?.progress)
        XCTAssertEqual(card?.buttonTitle, "Send")
        XCTAssertEqual(card?.accessibilityLabel, "\(ask), Send")
        XCTAssertFalse((card?.accessibilityLabel ?? "").contains("Thank someone"))
        XCTAssertFalse((card?.accessibilityLabel ?? "").contains("30 Days of Thanks"))
    }

    func testDuplicateThemeIsHiddenAndEmptyAskShowsNothing() {
        let same = CampaignPromptCardModel.content(
            feedTitle: "Remote title",
            day: 1,
            theme: ask,
            prompt: "  \(ask)  ",
            promptCTA: nil,
            feedCTA: nil,
            configCTA: nil,
            daysSent: 0,
            totalDays: 30
        )
        XCTAssertNil(same?.theme)
        XCTAssertEqual(same?.ask, ask)
        XCTAssertNil(
            CampaignPromptCardModel.content(
                feedTitle: "Remote title",
                day: 1,
                theme: "A mentor",
                prompt: "   ",
                promptCTA: "Send",
                feedCTA: nil,
                configCTA: nil,
                daysSent: 1,
                totalDays: 30
            )
        )
    }

    #if !canImport(CampaignPrompt)
    func testFeedDecodesRemoteCTAWithoutALocalTitleFallback() throws {
        let json = """
        {
          "id": "november-2026",
          "start": "2026-11-01",
          "end": "2026-11-30",
          "timezone": "America/New_York",
          "cta": " Send ",
          "prompts": [
            {
              "day": 5,
              "date": "2026-11-05",
              "theme": "A mentor",
              "prompt": "Thank a mentor who told you the truth.",
              "cta": "Send this note"
            }
          ]
        }
        """.data(using: .utf8)!

        let feed = try JSONDecoder().decode(CampaignFeed.self, from: json)
        XCTAssertEqual(feed.title, "")
        XCTAssertEqual(feed.cta, "Send")
        XCTAssertEqual(feed.prompts.first?.cta, "Send this note")
        XCTAssertNotEqual(feed.title, CampaignFeed.cardTitle)

        let card = CampaignPromptCardModel.content(
            feedTitle: feed.title,
            day: feed.prompts[0].day,
            theme: feed.prompts[0].theme,
            prompt: feed.prompts[0].prompt,
            promptCTA: feed.prompts[0].cta,
            feedCTA: feed.cta,
            configCTA: nil,
            daysSent: nil,
            totalDays: feed.inclusiveDayCount
        )
        XCTAssertEqual(card?.buttonTitle, "Send this note")
        XCTAssertNil(card?.eyebrow)
    }
    #endif
}
