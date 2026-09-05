import Foundation

enum AppGroup {
    static let identifier = "group.com.openthanks.ios"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
