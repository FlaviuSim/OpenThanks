import SwiftUI
import UIKit

/// Dedicated Appearance settings: Light / Dark / Auto theme + alternate app icons.
struct AppearanceView: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @AppStorage("appIconName") private var storedIconName = AppIconOption.default.storageValue
    @AppStorage(ThanksgivingThemeOverride.defaultsKey) private var thanksgivingOverride = ThanksgivingThemeOverride.automatic.rawValue
    @State private var iconError: String?

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .dark
    }

    private var selectedIcon: AppIconOption {
        AppIconOption(storageValue: storedIconName)
    }

    private var thanksgivingActive: Bool {
        ThanksgivingTheme.isActive(overrideRaw: thanksgivingOverride)
    }

    private var showsThanksgivingControls: Bool {
        #if DEBUG
        true
        #else
        thanksgivingActive || thanksgivingOverride != ThanksgivingThemeOverride.automatic.rawValue
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                themeSection
                iconSection
                if showsThanksgivingControls {
                    thanksgivingSection
                }
                if let iconError {
                    Text(iconError)
                        .font(Theme.body(13))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .tabChromeBottomPadding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.large)
        .syncAppAppearance()
        .onAppear {
            // Keep storage aligned with whatever icon is actually active.
            storedIconName = AppIconOption.current.storageValue
            ThanksgivingIconCoordinator.sync(overrideRaw: thanksgivingOverride)
        }
    }

    // MARK: Theme

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Theme")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: 12) {
                ForEach(AppAppearance.allCases) { option in
                    themeCard(option)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func themeCard(_ option: AppAppearance) -> some View {
        let selected = selectedAppearance == option
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                appearance = option.rawValue
            }
        } label: {
            VStack(spacing: 10) {
                ThemePreviewChip(style: option)
                    .frame(height: 118)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Theme.primary : Theme.hairline, lineWidth: selected ? 2 : 1)
                    )

                Text(option.title)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                selectionDot(selected: selected)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Icons

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App icon")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("The heart-O mark, in a few Home Screen finishes.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if thanksgivingActive {
                Text("Thanksgiving is available this week. iOS asks before it changes your icon.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                spacing: 16
            ) {
                ForEach(AppIconOption.pickerOptions(includingSeasonal: thanksgivingActive)) { option in
                    iconCard(option)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func iconCard(_ option: AppIconOption) -> some View {
        let selected = selectedIcon == option
        return Button {
            selectIcon(option)
        } label: {
            VStack(spacing: 8) {
                Image(uiImage: option.previewImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Theme.primary : Theme.hairline, lineWidth: selected ? 2 : 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)

                Text(option.title)
                    .font(Theme.body(11, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                selectionDot(selected: selected)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option == .thanksgiving ? "Thanksgiving app icon" : "\(option.title) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionDot(selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(selected ? Theme.primary : Theme.textTertiary.opacity(0.45), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .fill(Theme.primary)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.onPrimary)
            }
        }
    }

    private func selectIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons || option == .default else {
            iconError = "Alternate icons aren’t available on this device."
            return
        }
        iconError = nil
        if option == .thanksgiving {
            ThanksgivingIconCoordinator.useSeasonalIcon { message in
                if let message {
                    iconError = message
                } else {
                    storedIconName = option.storageValue
                }
            }
            return
        }
        ThanksgivingIconCoordinator.noteManualSelection(alternateIconName: option.alternateIconName)
        let name = option.alternateIconName
        // Avoid no-op calls that can flash the system alert.
        if UIApplication.shared.alternateIconName == name {
            storedIconName = option.storageValue
            return
        }
        UIApplication.shared.setAlternateIconName(name) { error in
            DispatchQueue.main.async {
                if let error {
                    iconError = error.localizedDescription
                } else {
                    storedIconName = option.storageValue
                    ThanksgivingIconCoordinator.noteChange()
                }
            }
        }
    }

    // MARK: Thanksgiving preview

    private var thanksgivingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Thanksgiving")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(thanksgivingCaption)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(ThanksgivingThemeOverride.allCases, id: \.rawValue) { option in
                    let selected = (ThanksgivingThemeOverride(rawValue: thanksgivingOverride) ?? .automatic) == option
                    Button {
                        thanksgivingOverride = option.rawValue
                        ThanksgivingIconCoordinator.sync(overrideRaw: option.rawValue)
                    } label: {
                        Text(thanksgivingOverrideTitle(option))
                            .font(Theme.body(13, weight: .semibold))
                            .foregroundStyle(selected ? Theme.onPrimary : Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background {
                                Capsule().fill(selected ? Theme.primary : Theme.surfaceRaised)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var thanksgivingCaption: String {
        let range = ThanksgivingTheme.spanLabel() ?? "the Monday before Thanksgiving through the Sunday after"
        switch ThanksgivingThemeOverride(rawValue: thanksgivingOverride) ?? .automatic {
        case .automatic:
            return thanksgivingActive
                ? "Seasonal artwork is on this week (\(range)). Automatic follows that window in your time zone."
                : "Seasonal artwork follows Thanksgiving week (\(range)) in your time zone. Turn it on to preview."
        case .on:
            return "Preview is on, including outside Thanksgiving week (\(range))."
        case .off:
            return "Seasonal artwork is hidden, including during Thanksgiving week (\(range))."
        }
    }

    private func thanksgivingOverrideTitle(_ option: ThanksgivingThemeOverride) -> String {
        switch option {
        case .automatic: "Automatic"
        case .on: "On"
        case .off: "Off"
        }
    }

    // MARK: - Theme preview chips

private struct ThemePreviewChip: View {
    let style: AppAppearance

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                switch style {
                case .light:
                    lightPreview(width: w, height: h)
                case .dark:
                    darkPreview(width: w, height: h)
                case .system:
                    HStack(spacing: 0) {
                        lightPreview(width: w / 2, height: h)
                            .frame(width: w / 2, height: h)
                            .clipped()
                        darkPreview(width: w / 2, height: h)
                            .frame(width: w / 2, height: h)
                            .clipped()
                    }
                }
            }
        }
    }

    private func lightPreview(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0xFFF5EE)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0xF65601).opacity(0.9))
                    .frame(width: width * 0.42, height: 7)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(height: height * 0.38)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(Color(hex: 0xFEE4D6))
                            .frame(width: width * 0.35, height: 6)
                            .padding(8)
                    }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0xF0D0BE))
                            .frame(height: 14)
                    }
                }
            }
            .padding(10)
        }
    }

    private func darkPreview(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x1A0C06)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0xF65601))
                    .frame(width: width * 0.42, height: 7)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0x2A140C))
                    .frame(height: height * 0.38)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(Color(hex: 0xFF8A4A))
                            .frame(width: width * 0.35, height: 6)
                            .padding(8)
                    }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0x3A1C10))
                            .frame(height: 14)
                    }
                }
            }
            .padding(10)
        }
    }
}

// MARK: - App icon options

enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case ember = "Ember"
    case dawn = "Dawn"
    case night = "Night"
    case thanksgiving = "Thanksgiving"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .thanksgiving: "Thanks"
        default: rawValue
        }
    }
    var storageValue: String { rawValue }

    /// Icons shown in Appearance. The seasonal icon is omitted outside Thanksgiving week.
    static func pickerOptions(includingSeasonal: Bool) -> [AppIconOption] {
        var options: [AppIconOption] = [.default, .ember, .dawn, .night]
        if includingSeasonal {
            options.append(.thanksgiving)
        }
        return options
    }

    /// `nil` restores the primary App Store icon.
    var alternateIconName: String? {
        switch self {
        case .default: nil
        case .ember: "AppIcon-Ember"
        case .dawn: "AppIcon-Dawn"
        case .night: "AppIcon-Night"
        case .thanksgiving: ThanksgivingIconPolicy.seasonalAlternateIconName
        }
    }

    init(storageValue: String) {
        self = AppIconOption(rawValue: storageValue) ?? .default
    }

    static var current: AppIconOption {
        let active = UIApplication.shared.alternateIconName
        return allCases.first { $0.alternateIconName == active } ?? .default
    }

    var previewImage: UIImage {
        let candidates = [
            "AppIcon-\(rawValue)-Preview",
            "AppIcon-\(rawValue)",
            "AppIcon-\(rawValue)@3x",
        ]
        for name in candidates {
            if let image = UIImage(named: name) { return image }
        }
        // Fallback: draw a tiny brand placeholder.
        let size = CGSize(width: 180, height: 180)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(Color(hex: 0xF65601)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let heart = UIImage(systemName: "heart.fill")?
                .withTintColor(UIColor.white, renderingMode: .alwaysOriginal)
            heart?.draw(in: CGRect(x: 45, y: 50, width: 90, height: 80))
        }
    }
}
