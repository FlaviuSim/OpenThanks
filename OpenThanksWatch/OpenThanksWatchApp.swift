import SwiftUI
import WatchConnectivity

@main
struct OpenThanksWatchApp: App {
    @State private var session = WatchPhoneSession.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(session)
                .onOpenURL { url in
                    if WatchDeepLink.isCompose(url) {
                        session.pendingComposeFocus = true
                    }
                }
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
