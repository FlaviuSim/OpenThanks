import Foundation
import UIKit

/// Soft App Store update check — never blocks the app.
/// Looks up the live marketing version at most once per day and drives a Home banner.
@MainActor
@Observable
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    private static let lastCheckKey = "appUpdate.lastCheckAt.v1"
    private static let storeVersionKey = "appUpdate.storeVersion.v1"
    private static let snoozeUntilKey = "appUpdate.snoozeUntil.v1"
    private static let snoozeVersionKey = "appUpdate.snoozeVersion.v1"
    private static let lastShownVersionKey = "appUpdate.lastShownVersion.v1"

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let snoozeDays = 7

    /// Latest App Store marketing version from the last successful lookup.
    private(set) var storeVersion: String? {
        didSet { refreshEligibility() }
    }

    /// True when Home should show the dismissible update banner.
    private(set) var shouldShowBanner = false

    private var checkTask: Task<Void, Never>?

    private init() {
        storeVersion = UserDefaults.standard.string(forKey: Self.storeVersionKey)
        refreshEligibility()
    }

    /// Installed marketing version (`1.2`), not build number.
    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Call on foreground / Home appear. No-ops when a check ran recently.
    func checkIfNeeded() {
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? TimeInterval,
           Date().timeIntervalSince1970 - last < Self.checkInterval {
            refreshEligibility()
            return
        }
        guard checkTask == nil else { return }
        checkTask = Task {
            defer { checkTask = nil }
            await lookupStoreVersion()
        }
    }

    func snooze() {
        guard let storeVersion else { return }
        let until = Date().timeIntervalSince1970 + Double(Self.snoozeDays) * 24 * 60 * 60
        UserDefaults.standard.set(until, forKey: Self.snoozeUntilKey)
        UserDefaults.standard.set(storeVersion, forKey: Self.snoozeVersionKey)
        Analytics.capture("app_update_banner_dismissed", [
            "store_version": storeVersion,
            "installed_version": installedVersion,
        ])
        refreshEligibility()
    }

    func openAppStore() {
        if let storeVersion {
            Analytics.capture("app_update_banner_tapped", [
                "store_version": storeVersion,
                "installed_version": installedVersion,
            ])
        }
        UIApplication.shared.open(AppConfig.appStoreProductURL)
    }

    // MARK: - Private

    private func lookupStoreVersion() async {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: AppConfig.appStoreID),
            // Bust intermediary caches lightly; Apple still rate-limits by IP.
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))),
        ]
        guard let url = components.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { return }

            struct LookupResponse: Decodable {
                let results: [Result]
                struct Result: Decodable {
                    let version: String?
                }
            }

            let decoded = try JSONDecoder().decode(LookupResponse.self, from: data)
            guard let version = decoded.results.first?.version?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !version.isEmpty
            else { return }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            UserDefaults.standard.set(version, forKey: Self.storeVersionKey)
            storeVersion = version
        } catch {
            // Silent — update nudge is best-effort.
        }
    }

    private func refreshEligibility() {
        guard let storeVersion,
              Self.isVersion(installedVersion, lessThan: storeVersion)
        else {
            shouldShowBanner = false
            return
        }

        if let snoozeVersion = UserDefaults.standard.string(forKey: Self.snoozeVersionKey),
           snoozeVersion == storeVersion,
           let until = UserDefaults.standard.object(forKey: Self.snoozeUntilKey) as? TimeInterval,
           Date().timeIntervalSince1970 < until {
            shouldShowBanner = false
            return
        }

        shouldShowBanner = true
    }

    /// Call from the banner’s `onAppear` so we only count real Home impressions.
    /// Once per store version (tab switches shouldn’t re-fire).
    func trackBannerShown() {
        guard let storeVersion else { return }
        let last = UserDefaults.standard.string(forKey: Self.lastShownVersionKey)
        guard last != storeVersion else { return }
        UserDefaults.standard.set(storeVersion, forKey: Self.lastShownVersionKey)
        Analytics.capture("app_update_banner_shown", [
            "store_version": storeVersion,
            "installed_version": installedVersion,
        ])
    }

    /// Semver-ish numeric compare: `1.2` < `1.2.1` < `1.3` < `2.0`.
    static func isVersion(_ lhs: String, lessThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a < b { return true }
            if a > b { return false }
        }
        return false
    }
}
