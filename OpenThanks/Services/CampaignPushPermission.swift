import Foundation

/// Whether the 30 Days of Thanks surfaces should ask for push permission.
///
/// The system dialog is only valid while iOS has never asked. Granted and
/// denied stay quiet. A second moment in the same app session does not ask
/// again — the person already saw the context sheet.
enum CampaignPushAuthorization: Equatable {
    case notDetermined
    case denied
    case authorized
}

enum CampaignPushMoment: Equatable {
    /// Home 30 Days card became visible.
    case openedScreen
    /// User started a 30 Days thank-you (card button or campaign link).
    case joined
}

enum CampaignPushPermission {
    /// Shown on the existing notification pre-prompt. Do not mention other devices.
    static let contextLine = "Get your daily 30 Days of Thanks prompt."
    static let contextDetail = "Allow notifications and the day's prompt can reach you."
    /// PostHog `source` on the existing push permission events.
    static let analyticsSource = "campaign"

    static func shouldRequest(
        _ status: CampaignPushAuthorization,
        moment: CampaignPushMoment,
        alreadyOfferedThisSession: Bool
    ) -> Bool {
        switch moment {
        case .openedScreen, .joined:
            return status == .notDetermined && !alreadyOfferedThisSession
        }
    }
}
