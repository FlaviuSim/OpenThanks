import SwiftUI
import UIKit

enum AppAppearance: String {
    case dark, light

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}

enum Theme {
    /// Dynamic UIColors so palette tracks `preferredColorScheme` without
    /// requiring every screen to observe `@AppStorage("appAppearance")`.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    private static func adaptive(light: UInt32, dark: UInt32, opacity: Double) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
    }

    // MARK: Palette — adaptive light/dark (dark is the default design)
    static var background: Color { adaptive(light: 0xF7F5F2, dark: 0x0A0A0B) }
    static var surface: Color { adaptive(light: 0xFFFFFF, dark: 0x161618) }
    static var surfaceRaised: Color { adaptive(light: 0xF0EDE8, dark: 0x1E1E21) }
    static var hairline: Color { adaptive(light: 0x000000, dark: 0xFFFFFF, opacity: 0.08) }
    static var textPrimary: Color { adaptive(light: 0x1A1A1B, dark: 0xF5F3F0) }
    static var textSecondary: Color { adaptive(light: 0x5C5C62, dark: 0x9B9B9F) }
    static var textTertiary: Color { adaptive(light: 0x8E8E93, dark: 0x6C6C70) }
    static let coral = Color(hex: 0xE07A5F)          // brand terracotta
    static let coralLight = Color(hex: 0xF4977F)
    static let coralPale = Color(hex: 0xF9C3A9)

    static var heartGradient: LinearGradient {
        LinearGradient(colors: [coralPale, coralLight, coral],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var ctaGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF9B49A), Color(hex: 0xED7B5B)],
                       startPoint: .leading, endPoint: .trailing)
    }

    // MARK: Type
    // Uses Fraunces / DM Sans if the TTFs are bundled (see README),
    // otherwise falls back to system serif / SF — no crash either way.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if UIFont(name: "Fraunces", size: size) != nil {
            return .custom("Fraunces", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: "DMSans-Regular", size: size) != nil {
            return .custom("DMSans-Regular", size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

}

// MARK: Appearance propagation

private struct SyncAppAppearanceModifier: ViewModifier {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue

    private var colorScheme: ColorScheme {
        AppAppearance(rawValue: appearance)?.colorScheme ?? .dark
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .animation(.easeInOut(duration: 0.2), value: appearance)
    }
}

extension View {
    /// Applies the user's light/dark preference and re-renders when it changes.
    func syncAppAppearance() -> some View {
        modifier(SyncAppAppearanceModifier())
    }
}

// MARK: Reusable chrome

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

struct CTAButtonStyle: ButtonStyle {
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !isLoading
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(Color(hex: 0x2B1209))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ctaGradient, in: Capsule())
            .overlay {
                if pressed {
                    Capsule().fill(Color.black.opacity(0.12))
                }
            }
            .opacity(isLoading ? 0.9 : 1)
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 14)
            .background(Theme.surfaceRaised, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct HeartMark: View {
    var size: CGFloat = 88
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: size))
            .foregroundStyle(Theme.heartGradient)
            .shadow(color: Theme.coral.opacity(0.45), radius: size / 4)
    }
}
