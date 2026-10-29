import Foundation

/// What “Send one like this” does when tapped on the Ripple tab.
///
/// Linux `swift test` compiles the identical copy at
/// `OpenThanksTests/Sources/RippleSend/RippleSend.swift`. Keep both copies the same.
enum RippleSend {
    static let analyticsEvent = "ripple_send_tapped"
    /// Distinct from `ripple_tab` (“Start your own ripple”) so the compose funnel can tell them apart.
    static let composeAnalyticsSource = "ripple_send_like_this"

    struct Example: Equatable {
        var id: UUID
        var recipientId: UUID?
        var authorName: String?
    }

    struct Launch: Equatable {
        var analyticsEvent: String
        var composeAnalyticsSource: String
        var isOwnProfile: Bool
        var profileId: String
        /// Set only when an on-screen example is an appreciation the viewer received.
        var inspiredByGratitudeId: UUID?
        var inspiredByAuthorName: String?

        /// Properties for `Analytics.capture`. Names stay off the event; `platform` is added by `Analytics`.
        func analyticsProperties() -> [String: Any] {
            var properties: [String: Any] = [
                "is_own_profile": isOwnProfile,
                "profile_id": profileId,
            ]
            if let inspiredByGratitudeId {
                properties["parent_gratitude_id"] = inspiredByGratitudeId.uuidString.lowercased()
            }
            return properties
        }
    }

    /// Blank compose, plus inspired-by context when one of `examples` was sent to `viewerId`.
    /// The first match wins so the prefill follows the appreciation nearest the button.
    static func launch(
        isOwnProfile: Bool,
        profileId: UUID,
        viewerId: UUID?,
        examples: [Example]
    ) -> Launch {
        let received = examples.first { example in
            guard let viewerId, let recipientId = example.recipientId else { return false }
            return recipientId == viewerId
        }
        let author = received?.authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Launch(
            analyticsEvent: analyticsEvent,
            composeAnalyticsSource: composeAnalyticsSource,
            isOwnProfile: isOwnProfile,
            profileId: profileId.uuidString.lowercased(),
            inspiredByGratitudeId: received?.id,
            inspiredByAuthorName: (author?.isEmpty == false) ? author : nil
        )
    }
}
