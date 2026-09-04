import AppIntents
import SwiftUI
import WidgetKit

/// Control Center (and Lock Screen / Action Button) shortcut — iOS 18+.
/// Intent is in this file so it can be compiled into both the app and widget
/// extension (Apple requires both memberships to open the app).
@available(iOS 18.0, *)
struct OpenComposeFromControlIntent: AppIntent {
    static var title: LocalizedStringResource = "Thank Someone"
    static var description = IntentDescription(
        "Opens OpenThanks to write a new appreciation."
    )
    static var openAppWhenRun = true
    static var isDiscoverable = true

    func perform() async throws -> some IntentResult & OpensIntent {
        // App Group survives when Control Center opens the app without delivering the URL.
        ControlCenterHandoff.markCompose()
        return .result(opensIntent: OpenURLIntent(WidgetDeepLink.compose))
    }
}

@available(iOS 18.0, *)
struct ThankSomeoneControl: ControlWidget {
    static let kind = "com.openthanks.app.thankSomeoneControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenComposeFromControlIntent()) {
                Label("Thank Someone", systemImage: "heart.fill")
            }
        }
        .displayName("Thank Someone")
        .description("Opens OpenThanks to write a new appreciation.")
    }
}
