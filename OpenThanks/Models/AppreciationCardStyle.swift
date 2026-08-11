import Foundation
import SwiftUI

/// Stories-style appreciation card layout (matches web `lib/card-style.ts`).
struct AppreciationCardStyle: Codable, Hashable, Sendable {
    var version: Int
    var backgroundId: BackgroundID
    var typePreset: TypePreset
    var textAlign: TextAlign

    enum BackgroundID: String, Codable, CaseIterable, Hashable, Sendable {
        case sunrise, coral_dusk, evergreen, golden_hour
        case lavender_mist, ink_night, paper, ocean_glass, blush
        case custom_media
    }

    enum TypePreset: String, Codable, CaseIterable, Hashable, Sendable {
        case display, hand, clean, bold
    }

    enum TextAlign: String, Codable, CaseIterable, Hashable, Sendable {
        case center, left
    }

    static let `default` = AppreciationCardStyle(
        version: 1,
        backgroundId: .sunrise,
        typePreset: .display,
        textAlign: .center
    )

    static let textMax = 280

    var usesLightText: Bool {
        switch backgroundId {
        case .coral_dusk, .evergreen, .ink_night, .custom_media:
            return true
        default:
            return false
        }
    }

    var label: String {
        switch backgroundId {
        case .sunrise: return "Sunrise"
        case .coral_dusk: return "Coral dusk"
        case .evergreen: return "Evergreen"
        case .golden_hour: return "Golden hour"
        case .lavender_mist: return "Lavender"
        case .ink_night: return "Ink night"
        case .paper: return "Paper"
        case .ocean_glass: return "Ocean"
        case .blush: return "Blush"
        case .custom_media: return "Photo"
        }
    }
}

enum AppreciationCardPresets {
    static let selectableBackgrounds: [AppreciationCardStyle.BackgroundID] = [
        .sunrise, .coral_dusk, .evergreen, .golden_hour,
        .lavender_mist, .ink_night, .paper, .ocean_glass, .blush,
    ]

    static func gradient(for id: AppreciationCardStyle.BackgroundID) -> LinearGradient {
        switch id {
        case .sunrise:
            return LinearGradient(
                colors: [Color(hex: 0xFFF8F2), Color(hex: 0xFFE4D6), Color(hex: 0xF5B89A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .coral_dusk:
            return LinearGradient(
                colors: [Color(hex: 0xC9604A), Color(hex: 0x9B4A6A), Color(hex: 0x5C3A55)],
                startPoint: .top, endPoint: .bottom
            )
        case .evergreen:
            return LinearGradient(
                colors: [Color(hex: 0x3FA87A), Color(hex: 0x2D7A5E), Color(hex: 0x1A4A3A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .golden_hour:
            return LinearGradient(
                colors: [Color(hex: 0xFFE9A8), Color(hex: 0xFFD6C9), Color(hex: 0xFFF8F2)],
                startPoint: .top, endPoint: .bottom
            )
        case .lavender_mist:
            return LinearGradient(
                colors: [Color(hex: 0xF7F3FF), Color(hex: 0xE8D5E8), Color(hex: 0xFFD6C9)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .ink_night:
            return LinearGradient(
                colors: [Color(hex: 0x1A1214), Color(hex: 0x2A1A1E), Color(hex: 0x0A0A0B)],
                startPoint: .top, endPoint: .bottom
            )
        case .paper:
            return LinearGradient(
                colors: [Color(hex: 0xFFFBF5), Color(hex: 0xF5EDE3)],
                startPoint: .top, endPoint: .bottom
            )
        case .ocean_glass:
            return LinearGradient(
                colors: [Color(hex: 0xD4EFE8), Color(hex: 0x7EB8C9), Color(hex: 0x4A9E9A)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .blush:
            return LinearGradient(
                colors: [Color(hex: 0xFFF0EB), Color(hex: 0xFFD6C9), Color(hex: 0xFFF8F2)],
                startPoint: .top, endPoint: .bottom
            )
        case .custom_media:
            return LinearGradient(colors: [.black, Color(hex: 0x1A1214)], startPoint: .top, endPoint: .bottom)
        }
    }

    static func font(for preset: AppreciationCardStyle.TypePreset, size: CGFloat) -> Font {
        switch preset {
        case .display:
            return Theme.display(size, weight: .semibold)
        case .hand:
            return Font.system(size: size, weight: .medium, design: .rounded)
        case .clean:
            return Theme.body(size, weight: .medium)
        case .bold:
            return Theme.display(size, weight: .bold)
        }
    }

    static func snippet(_ message: String, max: Int = AppreciationCardStyle.textMax) -> String {
        let trimmed = message
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: max - 1)
        return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
