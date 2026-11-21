import SwiftUI
import UIKit

/// Asset names and chrome for the Thanksgiving-week theme.
/// Views should read ``ThanksgivingTheme/isActive(overrideRaw:)`` so a debug
/// override refreshes through `@AppStorage`. Outside the window, with the
/// override left on automatic, none of these images are inserted.
enum ThanksgivingArtwork {
    static let turkey = "ThanksgivingTurkey"
    static let leaf = "ThanksgivingLeaf"
    static let leaves = "ThanksgivingLeaves"
    static let pie = "ThanksgivingPie"
    static let heart = "ThanksgivingHeart"
    static let wheat = "ThanksgivingWheat"
    static let success = "ThanksgivingSuccess"
}

struct ThanksgivingShortcut: Identifiable, Equatable {
    var emoji: String
    var asset: String
    var accessibilityLabel: String
    var id: String { emoji }
}

enum ThanksgivingAppreciation {
    /// Illustrated stand-ins for the compose shortcuts. Tapping still inserts an emoji.
    static let shortcuts: [ThanksgivingShortcut] = [
        .init(emoji: "🦃", asset: ThanksgivingArtwork.turkey, accessibilityLabel: "Insert turkey"),
        .init(emoji: "❤️", asset: ThanksgivingArtwork.heart, accessibilityLabel: "Insert heart"),
        .init(emoji: "🍂", asset: ThanksgivingArtwork.leaf, accessibilityLabel: "Insert autumn leaf"),
        .init(emoji: "🥧", asset: ThanksgivingArtwork.pie, accessibilityLabel: "Insert pie"),
        .init(emoji: "🧡", asset: ThanksgivingArtwork.wheat, accessibilityLabel: "Insert harvest"),
        .init(emoji: "🍁", asset: ThanksgivingArtwork.leaves, accessibilityLabel: "Insert maple leaves"),
    ]
}

enum ThanksgivingTheme {
    static func isActive(
        overrideRaw: String,
        at date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let override = ThanksgivingThemeOverride(rawValue: overrideRaw) ?? .automatic
        return ThanksgivingThemeGate.isActive(at: date, calendar: calendar, override: override)
    }

    /// "Nov 23 – Nov 29" in the device time zone, for the year that contains `date`.
    static func spanLabel(at date: Date = Date(), calendar: Calendar = .current) -> String? {
        let gregorian = ThanksgivingWindow.gregorian(timeZone: calendar.timeZone)
        let year = gregorian.component(.year, from: date)
        guard let span = ThanksgivingWindow.span(year: year, timeZone: calendar.timeZone) else { return nil }
        guard let lastInstant = gregorian.date(byAdding: .second, value: -1, to: span.end) else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return "\(formatter.string(from: span.start)) – \(formatter.string(from: lastInstant))"
    }
}

struct ThanksgivingDecal: View {
    var asset: String
    var size: CGFloat
    /// Set when the decal is the button's only content, so the control stays tappable.
    var interactive = false

    var body: some View {
        Image(asset)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .allowsHitTesting(interactive)
    }
}

enum ThanksgivingIconStore {
    static let optedInKey = "thanksgivingIconOptedIn"
    static let previousKey = "thanksgivingIconPrevious"
    static let dismissedYearKey = "thanksgivingIconDismissedYear"

    static var optedIn: Bool {
        UserDefaults.standard.bool(forKey: optedInKey)
    }

    /// Empty string means the primary icon. Missing means nothing was recorded.
    static var previousAlternateIconName: String? {
        guard UserDefaults.standard.object(forKey: previousKey) != nil else { return nil }
        return UserDefaults.standard.string(forKey: previousKey) ?? ""
    }

    static func recordOptIn(previousAlternateIconName: String?) {
        UserDefaults.standard.set(true, forKey: optedInKey)
        UserDefaults.standard.set(previousAlternateIconName ?? "", forKey: previousKey)
    }

    static func clearOptIn() {
        UserDefaults.standard.set(false, forKey: optedInKey)
        UserDefaults.standard.removeObject(forKey: previousKey)
    }
}

/// Applies the opt-in seasonal icon, and puts the previous icon back after the week.
/// Does not call `setAlternateIconName` just because the window opened.
@MainActor
enum ThanksgivingIconCoordinator {
    static let didChange = Notification.Name("thanksgivingIconDidChange")
    private static var restoreInFlight = false

    static func noteChange() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func sync(overrideRaw: String = UserDefaults.standard.string(forKey: ThanksgivingThemeOverride.defaultsKey) ?? "") {
        let themeActive = ThanksgivingTheme.isActive(overrideRaw: overrideRaw)
        let decision = ThanksgivingIconPolicy.action(
            themeActive: themeActive,
            optedIn: ThanksgivingIconStore.optedIn,
            previousAlternateIconName: ThanksgivingIconStore.previousAlternateIconName,
            activeAlternateIconName: UIApplication.shared.alternateIconName
        )
        switch decision {
        case .none:
            break
        case .clearOptIn:
            ThanksgivingIconStore.clearOptIn()
        case .setAlternateIcon(let name):
            guard !restoreInFlight else { return }
            guard UIApplication.shared.supportsAlternateIcons else { return }
            guard UIApplication.shared.alternateIconName != name else {
                ThanksgivingIconStore.clearOptIn()
                return
            }
            restoreInFlight = true
            UIApplication.shared.setAlternateIconName(name) { error in
                Task { @MainActor in
                    restoreInFlight = false
                    if error == nil {
                        ThanksgivingIconStore.clearOptIn()
                        noteChange()
                    }
                }
            }
        }
    }

    static func useSeasonalIcon(completion: @escaping (String?) -> Void) {
        guard UIApplication.shared.supportsAlternateIcons else {
            completion("Alternate icons aren’t available on this device.")
            return
        }
        let name = ThanksgivingIconPolicy.seasonalAlternateIconName
        if UIApplication.shared.alternateIconName == name {
            completion(nil)
            return
        }
        let previous = UIApplication.shared.alternateIconName
        ThanksgivingIconStore.recordOptIn(previousAlternateIconName: previous)
        UIApplication.shared.setAlternateIconName(name) { error in
            Task { @MainActor in
                if let error {
                    ThanksgivingIconStore.clearOptIn()
                    completion(error.localizedDescription)
                } else {
                    noteChange()
                    completion(nil)
                }
            }
        }
    }

    /// Manual pick from Appearance. Choosing anything other than the seasonal
    /// icon cancels the post-week restore, because the person made a new choice.
    static func noteManualSelection(alternateIconName: String?) {
        if alternateIconName == ThanksgivingIconPolicy.seasonalAlternateIconName {
            return
        }
        if ThanksgivingIconStore.optedIn {
            ThanksgivingIconStore.clearOptIn()
        }
    }
}

struct ThanksgivingIconOfferBanner: View {
    var seasonYear: Int
    @AppStorage(ThanksgivingIconStore.dismissedYearKey) private var dismissedYear = 0
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ThanksgivingDecal(asset: ThanksgivingArtwork.turkey, size: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Thanksgiving icon")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("A seasonal Home Screen icon for this week. iOS will ask you to confirm the change.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let error {
                Text(error)
                    .font(Theme.body(12))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button {
                    working = true
                    error = nil
                    ThanksgivingIconCoordinator.useSeasonalIcon { message in
                        working = false
                        error = message
                    }
                } label: {
                    Group {
                        if working {
                            ProgressView().tint(Theme.onPrimary)
                        } else {
                            Text("Use it")
                        }
                    }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.ctaGradient, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(working)
                .accessibilityLabel("Use the Thanksgiving app icon")

                Button {
                    dismissedYear = seasonYear
                } label: {
                    Text("Not now")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.surfaceRaised, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.hairline)
        )
        .accessibilityElement(children: .contain)
    }
}
