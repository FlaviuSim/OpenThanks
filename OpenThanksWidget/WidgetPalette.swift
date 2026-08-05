import SwiftUI
import UIKit

/// Lightweight palette for the widget extension (no UIKit Theme dependency).
enum WidgetPalette {
    static let coral = Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)

    static let background = Color(
        light: Color(red: 247 / 255, green: 245 / 255, blue: 242 / 255),
        dark: Color(red: 10 / 255, green: 10 / 255, blue: 11 / 255)
    )
    static let textPrimary = Color(
        light: Color(red: 26 / 255, green: 26 / 255, blue: 27 / 255),
        dark: Color(red: 245 / 255, green: 243 / 255, blue: 240 / 255)
    )
    static let textSecondary = Color(
        light: Color(red: 92 / 255, green: 92 / 255, blue: 98 / 255),
        dark: Color(red: 155 / 255, green: 155 / 255, blue: 159 / 255)
    )
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
