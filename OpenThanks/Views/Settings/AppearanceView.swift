import SwiftUI
import UIKit

/// Dedicated Appearance settings: Light / Dark / Auto theme + alternate app icons.
struct AppearanceView: View {
    @AppStorage("appAppearance") private var appearance = AppAppearance.dark.rawValue
    @AppStorage("appIconName") private var storedIconName = AppIconOption.default.storageValue
    @State private var iconError: String?

    private var selectedAppearance: AppAppearance {
        AppAppearance(rawValue: appearance) ?? .dark
    }

    private var selectedIcon: AppIconOption {
        AppIconOption(storageValue: storedIconName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                themeSection
                iconSection
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
                            .stroke(selected ? Theme.coral : Theme.hairline, lineWidth: selected ? 2 : 1)
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

            Text("A warmer look for your Home Screen — same OpenThanks heart.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                spacing: 16
            ) {
                ForEach(AppIconOption.allCases) { option in
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
                            .stroke(selected ? Theme.coral : Theme.hairline, lineWidth: selected ? 2 : 1)
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
        .accessibilityLabel("\(option.title) app icon")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func selectionDot(selected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(selected ? Theme.coral : Theme.textTertiary.opacity(0.45), lineWidth: 1.5)
                .frame(width: 20, height: 20)
            if selected {
                Circle()
                    .fill(Theme.coral)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func selectIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons || option == .default else {
            iconError = "Alternate icons aren’t available on this device."
            return
        }
        iconError = nil
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
                }
            }
        }
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
            Color(hex: 0xF7F5F2)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0xE07A5F).opacity(0.85))
                    .frame(width: width * 0.42, height: 7)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white)
                    .frame(height: height * 0.38)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(Color(hex: 0xF9C3A9))
                            .frame(width: width * 0.35, height: 6)
                            .padding(8)
                    }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0xF0EDE8))
                            .frame(height: 14)
                    }
                }
            }
            .padding(10)
        }
    }

    private func darkPreview(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x0A0A0B)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: 0xE07A5F))
                    .frame(width: width * 0.42, height: 7)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: 0x161618))
                    .frame(height: height * 0.38)
                    .overlay(alignment: .bottomLeading) {
                        Capsule()
                            .fill(Color(hex: 0xE07A5F).opacity(0.7))
                            .frame(width: width * 0.35, height: 6)
                            .padding(8)
                    }
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: 0x1E1E21))
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

    var id: String { rawValue }
    var title: String { rawValue }
    var storageValue: String { rawValue }

    /// `nil` restores the primary App Store icon.
    var alternateIconName: String? {
        switch self {
        case .default: nil
        case .ember: "AppIcon-Ember"
        case .dawn: "AppIcon-Dawn"
        case .night: "AppIcon-Night"
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
            UIColor(Color(hex: 0x1A0F0D)).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let heart = UIImage(systemName: "heart.fill")?
                .withTintColor(UIColor(Color(hex: 0xE07A5F)), renderingMode: .alwaysOriginal)
            heart?.draw(in: CGRect(x: 45, y: 50, width: 90, height: 80))
        }
    }
}
