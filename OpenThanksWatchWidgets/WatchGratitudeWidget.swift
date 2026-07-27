import WidgetKit
import SwiftUI

@main
struct OpenThanksWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchGratitudeWidget()
    }
}

struct WatchGratitudeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let prompt: WidgetPromptKind
}

struct WatchGratitudeProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchGratitudeEntry {
        makeEntry(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchGratitudeEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchGratitudeEntry>) -> Void) {
        let now = Date()
        var entries: [WatchGratitudeEntry] = []
        for hourOffset in stride(from: 0, through: 20, by: 4) {
            let date = Calendar.current.date(byAdding: .hour, value: hourOffset, to: now) ?? now
            entries.append(makeEntry(at: date))
        }
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: now)
            ?? now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func makeEntry(at date: Date) -> WatchGratitudeEntry {
        let snapshot = WidgetSnapshotStore.load()
        return WatchGratitudeEntry(
            date: date,
            snapshot: snapshot,
            prompt: WidgetPromptKind.prompt(at: date, snapshot: snapshot, family: nil)
        )
    }
}

struct WatchGratitudeWidget: Widget {
    let kind = "WatchGratitudeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchGratitudeProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.black.opacity(0.35)
                }
        }
        .configurationDisplayName("OpenThanks")
        .description("A gentle nudge to thank someone.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline,
        ])
    }
}

struct WatchComplicationView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchGratitudeEntry

    private let coral = Color(red: 224 / 255, green: 122 / 255, blue: 95 / 255)

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(coral)
                        Text("Thank")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
            case .accessoryCorner:
                Image(systemName: "heart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(coral)
                    .widgetLabel {
                        Text("Thank")
                    }
            case .accessoryInline:
                Label(inlineText, systemImage: "heart.fill")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Label("OpenThanks", systemImage: "heart.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(coral)
                    Text(rectangularHeadline)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if entry.snapshot.pendingToAccept > 0 {
                        Text(pendingLine)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Label("Thank someone", systemImage: "heart.fill")
            }
        }
        .widgetURL(WatchComposeURL.compose)
    }

    private var inlineText: String {
        if entry.snapshot.pendingToAccept > 0 {
            return pendingLine
        }
        return entry.prompt.headline(for: entry.snapshot)
    }

    private var rectangularHeadline: String {
        if entry.prompt == .monthlyCount {
            return entry.prompt.headline(for: entry.snapshot)
        }
        return entry.prompt.headline(for: entry.snapshot)
    }

    private var pendingLine: String {
        let n = entry.snapshot.pendingToAccept
        return n == 1 ? "1 waiting" : "\(n) waiting"
    }
}

/// Mirrors WatchDeepLink.compose without importing the Watch app module.
enum WatchComposeURL {
    static let compose = URL(string: "openthanks-watch://compose")!
}
