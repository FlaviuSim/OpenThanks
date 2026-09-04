import Foundation

/// Control Center → app handoff. iOS 18 Control widgets often launch the app
/// without delivering `OpenURLIntent`, so we also stash intent in the App Group.
enum ControlCenterHandoff {
    private static let composeKey = "controlCenter.pendingCompose.v1"

    static func markCompose() {
        AppGroup.defaults.set(true, forKey: composeKey)
        AppGroup.defaults.synchronize()
    }

    /// Returns true once, then clears.
    static func consumeCompose() -> Bool {
        guard AppGroup.defaults.bool(forKey: composeKey) else { return false }
        AppGroup.defaults.removeObject(forKey: composeKey)
        AppGroup.defaults.synchronize()
        return true
    }
}
