import Foundation
import UIKit

/// App Store update check — never blocks the app.
/// Looks up the live marketing version at most once per day.
/// The shell banner shows on every tab while this install is behind the store,
/// including on top of the first-send tip. Later hides it until the next day.
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
    /// Later is a pause, not a dismissal of the update.
    private static let snoozeInterval: TimeInterval = 24 * 60 * 60

    /// Latest App Store marketing version from the last successful lookup.
    private(set) var storeVersion: String? {
        didSet { refreshEligibility() }
    }

    /// True when the shell should show the update banner.
    private(set) var shouldShowBanner = false

    private var checkTask: Task<Void, Never>?

    private init() {
        // Don't publish from init — Home seeds `@State = .shared` during the
        // first view update. `checkIfNeeded()` loads disk + eligibility after.
    }

    /// Installed marketing version (`1.2`), not build number.
    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Call on launch and whenever the app becomes active. Skips the network when a check already succeeded today.
    func checkIfNeeded() {
        if storeVersion == nil {
            storeVersion = UserDefaults.standard.string(forKey: Self.storeVersionKey)
        }
        refreshEligibility()
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? TimeInterval,
           storeVersion != nil,
           Date().timeIntervalSince1970 - last < Self.checkInterval {
            return
        }
        guard checkTask == nil else { return }
        checkTask = Task {
            defer { checkTask = nil }
            if await lookupStoreVersion() { return }
            // One same-session retry. A failed lookup must not wait until tomorrow.
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            _ = await lookupStoreVersion()
        }
    }

    func snooze() {
        guard let storeVersion else { return }
        let until = Date().timeIntervalSince1970 + Self.snoozeInterval
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

    /// Returns true when Apple returned a version. Failures leave the last check unset so the next foreground tries again.
    private func lookupStoreVersion() async -> Bool {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: AppConfig.appStoreID),
            // Bust intermediary caches lightly; Apple still rate-limits by IP.
            URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970))),
        ]
        guard let url = components.url else { return false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else { return false }

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
            else { return false }

            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            UserDefaults.standard.set(version, forKey: Self.storeVersionKey)
            storeVersion = version
            // Diagnostic only — explains why the banner may never show (store == installed).
            Analytics.capture("app_update_check_completed", [
                "installed_version": installedVersion,
                "store_version": version,
                "update_available": Self.isVersion(installedVersion, lessThan: version),
            ])
            return true
        } catch {
            // Silent — update nudge is best-effort. Caller retries once.
            return false
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

    /// Call from the banner’s `onAppear` so we only count real impressions.
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
    nonisolated static func isVersion(_ lhs: String, lessThan rhs: String) -> Bool {
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
