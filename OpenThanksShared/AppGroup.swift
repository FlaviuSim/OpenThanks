import Foundation

enum AppGroup {
    static let identifier = "group.com.openthanks.gratitude"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
