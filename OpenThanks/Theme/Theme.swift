import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .system: "Auto"
        }
    }

    /// `nil` follows the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
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

    /// Centered reading column on iPad / regular width — keeps notes note-sized.
    static let readableMaxWidth: CGFloat = 600

    /// Bottom clearance for the floating iPhone tab bar; unused when sidebar is shown.
    static let phoneTabBarClearance: CGFloat = 96
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

    private var colorScheme: ColorScheme? {
        AppAppearance(rawValue: appearance)?.colorScheme
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(colorScheme)
            .animation(.easeInOut(duration: 0.2), value: appearance)
    }
}

extension View {
    /// Applies the user's Light / Dark / Auto preference.
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

    /// Caps width and centers content for comfortable reading on iPad.
    func readableWidth(_ maxWidth: CGFloat = Theme.readableMaxWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Phone tab-bar clearance on compact; normal safe-area padding on regular (sidebar).
    func tabChromeBottomPadding() -> some View {
        modifier(TabChromeBottomPaddingModifier())
    }

    /// Full-screen compose on iPhone; centered form sheet on iPad regular width.
    func composeCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(ComposeCoverModifier(isPresented: isPresented, content: content))
    }

    func composeCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(ComposeCoverItemModifier(item: item, content: content))
    }
}

private struct TabChromeBottomPaddingModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.padding(
            .bottom,
            sizeClass == .regular ? 24 : Theme.phoneTabBarClearance
        )
    }
}

private struct ComposeCoverModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> SheetContent
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var useSheet: Bool { sizeClass == .regular }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: sheetPresented) {
                self.content()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .syncAppAppearance()
            }
            .fullScreenCover(isPresented: fullScreenPresented) {
                self.content().syncAppAppearance()
            }
    }

    private var sheetPresented: Binding<Bool> {
        Binding(
            get: { useSheet && isPresented },
            set: { if useSheet { isPresented = $0 } }
        )
    }

    private var fullScreenPresented: Binding<Bool> {
        Binding(
            get: { !useSheet && isPresented },
            set: { if !useSheet { isPresented = $0 } }
        )
    }
}

private struct ComposeCoverItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Binding var item: Item?
    @ViewBuilder var content: (Item) -> SheetContent
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var useSheet: Bool { sizeClass == .regular }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheetItem) { value in
                self.content(value)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                    .syncAppAppearance()
            }
            .fullScreenCover(item: fullScreenItem) { value in
                self.content(value).syncAppAppearance()
            }
    }

    private var sheetItem: Binding<Item?> {
        Binding(
            get: { useSheet ? item : nil },
            set: { if useSheet { item = $0 } }
        )
    }

    private var fullScreenItem: Binding<Item?> {
        Binding(
            get: { useSheet ? nil : item },
            set: { if !useSheet { item = $0 } }
        )
    }
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

/// Solid brand badge for action rows — white glyph on coral for contrast.
struct ActionGlyph: View {
    let systemImage: String
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.coral)
                .frame(width: size, height: size)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(Color.white)
                .symbolRenderingMode(.monochrome)
        }
        .accessibilityHidden(true)
    }
}

/// Opens WhatsApp with a prefilled message (and optional phone).
/// Uses `https://wa.me` so it works without an Info.plist query scheme.
enum ShareChannels {
    static func whatsAppURL(message: String, phone: String? = nil) -> URL? {
        let digits = phone?.filter(\.isNumber) ?? ""
        let base = digits.count >= 8
            ? "https://wa.me/\(digits)"
            : "https://wa.me/"
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        return components?.url
    }
}

/// Tappable row used on share / nudge surfaces (text, email, edit, etc.).
struct ShareActionRow: View {
    let title: String
    let systemImage: String
    var subtitle: String? = nil
    var showSpinner = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ActionGlyph(systemImage: systemImage, size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.body(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if showSpinner {
                    ProgressView().tint(Theme.coral)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.hairline)
            )
            .opacity(disabled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Shown when reviewing a pending appreciation so the recipient knows
/// whether accepting will publish it or keep it between them and the sender.
struct AppreciationVisibilityNote: View {
    let visibility: GratitudeVisibility?

    private var isPrivate: Bool { visibility == .private }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPrivate ? "lock.fill" : "globe")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.coral)
                .frame(width: 28, height: 28)
                .background(Theme.coral.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isPrivate ? "Private" : "Public")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isPrivate
                     ? "Only you and the sender will see this if you accept."
                     : "Anyone on OpenThanks can see this if you accept.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Banner linking to Pending Appreciations — Home, Profile, Notifications.
struct PendingAppreciationsBanner: View {
    let count: Int

    var body: some View {
        NavigationLink(value: PendingAppreciationsRoute()) {
            HStack(spacing: 14) {
                ActionGlyph(systemImage: "clock.arrow.circlepath", size: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(count == 1
                         ? "1 appreciation still pending"
                         : "\(count) appreciations still pending")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("No one has accepted it yet")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.coral.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.coral.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

