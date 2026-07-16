import SwiftUI

enum Theme {
    // MARK: Palette (sampled from the design)
    static let background = Color(hex: 0x0A0A0B)
    static let surface = Color(hex: 0x161618)
    static let surfaceRaised = Color(hex: 0x1E1E21)
    static let hairline = Color.white.opacity(0.08)
    static let textPrimary = Color(hex: 0xF5F3F0)
    static let textSecondary = Color(hex: 0x9B9B9F)
    static let textTertiary = Color(hex: 0x6C6C70)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(Color(hex: 0x2B1209))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ctaGradient, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
