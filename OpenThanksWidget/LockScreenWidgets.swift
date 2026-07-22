import WidgetKit
import SwiftUI

// MARK: - Lock Screen / Home: Send thanks

struct SendThanksWidget: Widget {
    let kind = "SendThanksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GratitudeTimelineProvider()) { entry in
            SendThanksView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("Send thanks")
        .description("One-tap gratitude prompt.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct SendThanksView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GratitudeEntry

    var body: some View {
        Link(destination: WidgetDeepLink.compose) {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 2) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Thanks")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send thanks")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Write an appreciation")
                            .font(.system(size: 12))
                            .opacity(0.75)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                Label("Send thanks", systemImage: "heart.fill")
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WidgetPalette.coral)
                    Spacer(minLength: 0)
                    Text("Send thanks")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(WidgetPalette.textPrimary)
                    Text("One tap to write")
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetPalette.textSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Lock Screen / Home: View received

struct ReceivedThanksWidget: Widget {
    let kind = "ReceivedThanksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GratitudeTimelineProvider()) { entry in
            ReceivedThanksView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("View received thanks")
        .description("Open appreciations waiting for you.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

struct ReceivedThanksView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GratitudeEntry

    var body: some View {
        Link(destination: WidgetDeepLink.received) {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "envelope.open.fill")
                            .font(.system(size: 15, weight: .semibold))
                        if entry.snapshot.pendingToAccept > 0 {
                            Text("\(min(entry.snapshot.pendingToAccept, 99))")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Text("Inbox")
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 10) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Received thanks")
                            .font(.system(size: 14, weight: .semibold))
                        Text(receivedSubtitle)
                            .font(.system(size: 12))
                            .opacity(0.75)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            case .accessoryInline:
                if entry.snapshot.pendingToAccept > 0 {
                    Label("\(entry.snapshot.pendingToAccept) waiting", systemImage: "envelope.open.fill")
                } else {
                    Label("View received thanks", systemImage: "envelope.open.fill")
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(WidgetPalette.coral)
                    Spacer(minLength: 0)
                    Text("View received")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(WidgetPalette.textPrimary)
                    Text(receivedSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private var receivedSubtitle: String {
        let pending = entry.snapshot.pendingToAccept
        if pending == 1 { return "1 appreciation waiting" }
        if pending > 1 { return "\(pending) appreciations waiting" }
        if entry.snapshot.receivedTotal > 0 {
            return "See what you’ve received"
        }
        return "Nothing waiting — yet"
    }
}
