import Foundation

/// Matches `GratitudeStatus` in the app target so `StreakMath.swift` compiles here.
enum GratitudeStatus: String, Codable {
    case pending, accepted, rejected
}
