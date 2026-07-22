import WidgetKit
import SwiftUI

@main
struct OpenThanksWidgetBundle: WidgetBundle {
    var body: some Widget {
        GratitudePromptWidget()
        SendThanksWidget()
        ReceivedThanksWidget()
    }
}
