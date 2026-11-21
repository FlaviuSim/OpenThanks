import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    /// Shipping default — also the `@AppStorage` fallback when unset.
    case dark
    case light
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

    // MARK: Palette — Jonny #05
    // Same tokens as openthanks.com (`app/globals.css`). Asset-catalog
    // color sets (Brand, BrandButton, BrandSoft, BrandTint, Ink,
    // SecondaryText, AccentColor, LaunchBackground) mirror these hexes.
    static var background: Color { adaptive(light: 0xFFF5EE, dark: 0x1A0C06) }
    static var surface: Color { adaptive(light: 0xFFFFFF, dark: 0x2A140C) }
    static var surfaceRaised: Color { adaptive(light: 0xFEE4D6, dark: 0x3A1C10) }
    static var hairline: Color { adaptive(light: 0xF0D0BE, dark: 0x4A2A1C) }
    static var textPrimary: Color { adaptive(light: 0x2C0F00, dark: 0xFFF5EE) }
    static var textSecondary: Color { adaptive(light: 0x6B5448, dark: 0xE7C8B6) }
    static var textTertiary: Color { adaptive(light: 0x8A6E62, dark: 0xC4A394) }

    /// Logo, hearts, and large display accents. #F65601
    static var brand: Color { Color(hex: 0xF65601) }
    /// Rings and soft highlights. #FAA273
    static var brandSoft: Color { Color(hex: 0xFAA273) }
    /// Chips and soft fills. #FEE4D6 on light, #3A1C10 on dark.
    static var brandTint: Color { adaptive(light: 0xFEE4D6, dark: 0x3A1C10) }
    /// Buttons, links, and small text. #CC4701 on light, #FF8A4A on dark.
    static var primary: Color { adaptive(light: 0xCC4701, dark: 0xFF8A4A) }
    /// Label on ``primary`` fills. White on the deep button, ink on the lighter dark button.
    static var onPrimary: Color { adaptive(light: 0xFFFFFF, dark: 0x2C0F00) }

    /// Large brand mark. Prefer ``primary`` for links and small labels.
    static var coral: Color { brand }
    static var coralLight: Color { brandSoft }
    static var coralPale: Color { brandTint }

    static var heartGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFF7A33), brand, Color(hex: 0xE24E00)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Flat brand button. Kept as a gradient so existing fills stay one call.
    static var ctaGradient: LinearGradient {
        LinearGradient(colors: [primary, primary], startPoint: .leading, endPoint: .trailing)
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

    /// UIKit face matching ``body`` — keeps UITextView caret aligned with glyphs.
    static func uiBodyFont(size: CGFloat = 16, weight: UIFont.Weight = .regular) -> UIFont {
        let baseName: String? = {
            switch weight {
            case .semibold, .bold, .heavy, .black:
                if UIFont(name: "DMSans-SemiBold", size: size) != nil { return "DMSans-SemiBold" }
                if UIFont(name: "DMSans-Bold", size: size) != nil { return "DMSans-Bold" }
                return UIFont(name: "DMSans-Regular", size: size) != nil ? "DMSans-Regular" : nil
            case .medium:
                if UIFont(name: "DMSans-Medium", size: size) != nil { return "DMSans-Medium" }
                return UIFont(name: "DMSans-Regular", size: size) != nil ? "DMSans-Regular" : nil
            default:
                return UIFont(name: "DMSans-Regular", size: size) != nil ? "DMSans-Regular" : nil
            }
        }()
        if let baseName, let font = UIFont(name: baseName, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    /// Centered reading column on iPad / regular width — keeps notes note-sized.
    static let readableMaxWidth: CGFloat = 600

    /// Bottom clearance for the floating iPhone pill + FAB; unused when sidebar is shown.
    static let phoneTabBarClearance: CGFloat = 88
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Jonny #05 mark. Large accents and the logo.
    static var brand: Color { Theme.brand }
    /// #FAA273 rings and soft highlights.
    static var brandSoft: Color { Theme.brandSoft }
    /// #FEE4D6 chips, with a warm dark fill.
    static var brandTint: Color { Theme.brandTint }
    /// Accessible button and link orange (#CC4701 / #FF8A4A).
    static var brandButton: Color { Theme.primary }
    /// Foreground that sits on ``brandButton``.
    static var onBrandButton: Color { Theme.onPrimary }
}

// MARK: Appearance propagation

private struct SyncAppAppearanceModifier: ViewModifier {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue

    private var colorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearance) ?? .dark).colorScheme
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
    /// Locked for the lifetime of an open compose so Stage Manager size-class
    /// flips don’t tear sheet ↔ fullScreenCover mid-draft.
    @State private var lockedUseSheet: Bool?

    private var useSheet: Bool { lockedUseSheet ?? (sizeClass == .regular) }

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
            .onChange(of: isPresented) { _, open in
                if open {
                    if lockedUseSheet == nil {
                        lockedUseSheet = sizeClass == .regular
                    }
                } else {
                    lockedUseSheet = nil
                }
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
    @State private var lockedUseSheet: Bool?

    private var useSheet: Bool { lockedUseSheet ?? (sizeClass == .regular) }
    private var isOpen: Bool { item != nil }

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
            .onChange(of: isOpen) { _, open in
                if open {
                    if lockedUseSheet == nil {
                        lockedUseSheet = sizeClass == .regular
                    }
                } else {
                    lockedUseSheet = nil
                }
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

/// Soft empty column for iPad list↔detail shells.
struct SplitDetailPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ActionGlyph(systemImage: systemImage, size: 72)
            VStack(spacing: 8) {
                Text(title)
                    .font(Theme.display(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(40)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .combine)
    }
}

struct CTAButtonStyle: ButtonStyle {
    var isLoading = false
    /// Pass false when the button is disabled. This style otherwise keeps the
    /// full coral fill, so Save looks tappable when it isn't.
    var isEnabled = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !isLoading && isEnabled
        configuration.label
            .font(Theme.body(17, weight: .semibold))
            .foregroundStyle(Theme.onPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.ctaGradient, in: Capsule())
            .overlay {
                if pressed {
                    Capsule().fill(Color.black.opacity(0.12))
                }
            }
            .opacity(!isEnabled && !isLoading ? 0.4 : (isLoading ? 0.9 : 1))
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
            .shadow(color: Theme.brand.opacity(0.45), radius: size / 4)
    }
}

/// Stacked OPENTHANKS wordmark (Jonny #05). Orange on transparent.
struct BrandWordmark: View {
    var height: CGFloat = 64

    var body: some View {
        Image("BrandWordmark")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("OpenThanks")
    }
}

/// Heart-inside-O mark. Orange on transparent, so it sits on cream or warm dark.
struct BrandMark: View {
    var size: CGFloat = 36

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
                    ProgressView().tint(Theme.primary)
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
                .foregroundStyle(Theme.primary)
                .frame(width: 28, height: 28)
                .background(Theme.coral.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(isPrivate ? "Private" : "Public")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isPrivate
                     ? "Only you and the sender can see it"
                     : "In the feed once you accept")
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
                    Text("Share a link with them")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primary)
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

