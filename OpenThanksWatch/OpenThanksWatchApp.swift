import SwiftUI
import UserNotifications
import WatchKit

@main
struct OpenThanksWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var session = WatchPhoneSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .onOpenURL { url in
                    if WatchDeepLink.isCompose(url) {
                        session.requestCompose(autoRecord: true)
                    }
                }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        WatchComposeNotification.registerCategories()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard WatchComposeNotification.shouldOpenCompose(from: response) else { return }
        await MainActor.run {
            WatchPhoneSession.shared.requestCompose(autoRecord: true)
        }
    }
}

enum WatchDeepLink {
    static let scheme = "openthanks-watch"

    static var compose: URL {
        URL(string: "\(scheme)://compose")!
    }

    static func isCompose(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }
        let host = (url.host ?? "").lowercased()
        return host == "compose" || host == "thank" || host.isEmpty
    }
}
