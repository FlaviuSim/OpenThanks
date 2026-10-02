import Foundation

/// Soft post-send “Enjoying OpenThanks?” gate → App Store review or private feedback.
/// Throttled so the first send stays about sharing, not ratings.
enum EnjoymentPrompt {
    private static let sendCountKey = "enjoymentPrompt.successfulSendCount.v1"
    private static let completedKey = "enjoymentPrompt.completed.v1"
    private static let dismissedAtKey = "enjoymentPrompt.dismissedAt.v1"
    private static let receiveReviewAtKey = "appStoreReviewRequestedAfterReceiveAt.v1"

    static let writeReviewURL = URL(
        string: "https://apps.apple.com/app/id6808840343?action=write-review"
    )!

    private static let minSendsBeforeAsk = 2
    private static let dismissCooldownDays = 45
    private static let receiveReviewSkipDays = 14

    /// When SuccessView is torn down for Edit, skip treating sheet close as a dismiss.
    static var ignoreNextSheetDismiss = false

    /// Successful create (not edit) count on this device.
    static var successfulSendCount: Int {
        UserDefaults.standard.integer(forKey: sendCountKey)
    }

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func recordSuccessfulSend() {
        let next = successfulSendCount + 1
        UserDefaults.standard.set(next, forKey: sendCountKey)
    }

    /// Call when the receive-side StoreKit prompt fires so we don’t double-ask.
    static func recordReceiveSideReviewRequested() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: receiveReviewAtKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: dismissedAtKey)
    }

    static func markDismissed() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: dismissedAtKey)
    }

    /// Whether SuccessView should schedule the enjoyment sheet for this gratitude.
    static func shouldPresent(for gratitude: Gratitude) -> Bool {
        guard !hasCompleted else { return false }
        guard successfulSendCount >= minSendsBeforeAsk else { return false }
        // Don’t interrupt incomplete Watch drafts that still need a recipient.
        guard !gratitude.hasNoRecipient else { return false }

        if let dismissedAt = UserDefaults.standard.object(forKey: dismissedAtKey) as? TimeInterval {
            let days = Date().timeIntervalSince1970 - dismissedAt
            if days < Double(dismissCooldownDays) * 24 * 60 * 60 {
                return false
            }
        }

        if let receiveAt = UserDefaults.standard.object(forKey: receiveReviewAtKey) as? TimeInterval {
            let days = Date().timeIntervalSince1970 - receiveAt
            if days < Double(receiveReviewSkipDays) * 24 * 60 * 60 {
                return false
            }
        } else if AppStoreReviewPrompt.hasRequested {
            // Legacy bool without timestamp — treat as recent enough to skip once.
            return false
        }

        return true
    }
}
