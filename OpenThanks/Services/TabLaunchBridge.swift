import Foundation
import Observation

extension Notification.Name {
    static let tabLaunchQueued = Notification.Name("openthanks.tabLaunchQueued")
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
