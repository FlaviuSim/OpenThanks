import SwiftUI
import UIKit

/// Lightweight palette for the widget extension (no UIKit Theme dependency).
/// Hexes match `Theme` and openthanks.com Jonny #05.
enum WidgetPalette {
    /// Logo and large accents. #F65601
    static let coral = Color(red: 246 / 255, green: 86 / 255, blue: 1 / 255)
    static let brand = coral
    /// Buttons, links, and small text. #CC4701 / #FF8A4A
    static let primary = Color(
        light: Color(red: 204 / 255, green: 71 / 255, blue: 1 / 255),
        dark: Color(red: 255 / 255, green: 138 / 255, blue: 74 / 255)
    )
    static let brandSoft = Color(red: 250 / 255, green: 162 / 255, blue: 115 / 255)
    /// Label on ``primary``. White on light, ink on the lighter dark button.
    static let onPrimary = Color(
        light: Color.white,
        dark: Color(red: 44 / 255, green: 15 / 255, blue: 0 / 255)
    )

    static let background = Color(
        light: Color(red: 255 / 255, green: 245 / 255, blue: 238 / 255),
        dark: Color(red: 26 / 255, green: 12 / 255, blue: 6 / 255)
    )
    static let textPrimary = Color(
        light: Color(red: 44 / 255, green: 15 / 255, blue: 0 / 255),
        dark: Color(red: 255 / 255, green: 245 / 255, blue: 238 / 255)
    )
    static let textSecondary = Color(
        light: Color(red: 107 / 255, green: 84 / 255, blue: 72 / 255),
        dark: Color(red: 231 / 255, green: 200 / 255, blue: 182 / 255)
    )
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
