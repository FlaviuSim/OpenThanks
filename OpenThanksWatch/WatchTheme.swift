import SwiftUI

/// Jonny #05 brand palette for watchOS — matches iOS `Theme` / brand packet.
enum WatchTheme {
    /// Logo, hearts, large accents. #F65601
    static let brand = Color(red: 246 / 255, green: 86 / 255, blue: 1 / 255)
    /// Soft rings / secondary accents. #FAA273
    static let brandSoft = Color(red: 250 / 255, green: 162 / 255, blue: 115 / 255)
    /// Chips / soft fills on dark Watch chrome. #3A1C10
    static let brandTint = Color(red: 58 / 255, green: 28 / 255, blue: 16 / 255)
    /// Primary buttons (readable white label). #CC4701
    static let button = Color(red: 204 / 255, green: 71 / 255, blue: 1 / 255)
    /// Lighter control tint when needed. #FF8A4A
    static let buttonBright = Color(red: 255 / 255, green: 138 / 255, blue: 74 / 255)
    /// Warm secondary text on dark Watch UI. #E7C8B6
    static let textSecondary = Color(red: 231 / 255, green: 200 / 255, blue: 182 / 255)
    /// Tertiary / footnotes. #C4A394
    static let textTertiary = Color(red: 196 / 255, green: 163 / 255, blue: 148 / 255)
    /// Cream background (rare on Watch; matches light brand). #FFF5EE
    static let background = Color(red: 255 / 255, green: 245 / 255, blue: 238 / 255)
    /// Ink. #2C0F00
    static let ink = Color(red: 44 / 255, green: 15 / 255, blue: 0 / 255)

    /// Alias used historically in Watch UI.
    static var coral: Color { brand }
}
