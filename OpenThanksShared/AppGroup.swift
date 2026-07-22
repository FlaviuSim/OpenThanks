import Foundation

enum AppGroup {
    static let identifier = "group.com.openthanks.app"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
