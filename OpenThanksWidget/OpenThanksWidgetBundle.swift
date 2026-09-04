import WidgetKit
import SwiftUI

@main
struct OpenThanksWidgetBundle: WidgetBundle {
    var body: some Widget {
        StreakLiveActivityWidget()
        GratitudePromptWidget()
        SendThanksWidget()
        ReceivedThanksWidget()
        if #available(iOS 18.0, *) {
            ThankSomeoneControl()
        }
    }
}
