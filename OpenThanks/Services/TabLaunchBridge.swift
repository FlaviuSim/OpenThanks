import Foundation
import Observation

extension Notification.Name {
    static let tabLaunchQueued = Notification.Name("openthanks.tabLaunchQueued")
    /// Own-profile UserProfileView should select the People inspired section.
    static let focusProfileInspired = Notification.Name("openthanks.focusProfileInspired")
}

/// Switches main tabs from widgets / deep links (e.g. open received thanks on Home).
@Observable
@MainActor
final class TabLaunchBridge {
    static let shared = TabLaunchBridge()

    enum Destination: Equatable {
        case feed
        case received
        case home
        case notifications
        /// Own Profile tab, People inspired section (weekly hearts email).
        case profileInspired
    }

    private(set) var pending: Destination?

    func queue(_ destination: Destination) {
        pending = destination
        NotificationCenter.default.post(name: .tabLaunchQueued, object: nil)
    }

    func consume() -> Destination? {
        let next = pending
        pending = nil
        return next
    }
}
