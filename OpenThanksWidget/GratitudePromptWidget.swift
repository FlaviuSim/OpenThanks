import WidgetKit
import SwiftUI

struct GratitudeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let prompt: WidgetPromptKind
}

struct GratitudeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GratitudeEntry {
        GratitudeEntry(
            date: .now,
            snapshot: WidgetSnapshot(
                displayName: nil,
                sentThisMonth: 3,
                receivedTotal: 2,
                pendingToAccept: 1,
                updatedAt: .now
            ),
            prompt: .whoHelped
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GratitudeEntry) -> Void) {
        completion(makeEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GratitudeEntry>) -> Void) {
        let now = Date()
        var entries: [GratitudeEntry] = []
        for hourOffset in stride(from: 0, through: 18, by: 6) {
            let date = Calendar.current.date(byAdding: .hour, value: hourOffset, to: now) ?? now
            entries.append(makeEntry(at: date))
        }
        let next = Calendar.current.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(6 * 3600)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func makeEntry(at date: Date) -> GratitudeEntry {
        let snapshot = WidgetSnapshotStore.load()
        return GratitudeEntry(
            date: date,
            snapshot: snapshot,
            prompt: WidgetPromptKind.prompt(at: date, snapshot: snapshot)
        )
    }
}

/// Home Screen — rotating gratitude prompts.
struct GratitudePromptWidget: Widget {
    let kind = "GratitudePromptWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GratitudeTimelineProvider()) { entry in
            GratitudePromptView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.background
                }
        }
        .configurationDisplayName("Daily gratitude")
        .description("A quiet prompt to thank someone — or notice who thanked you.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct GratitudePromptView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GratitudeEntry

    var body: some View {
        Link(destination: entry.prompt.deepLink) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.coral)
                    Text("OpenThanks")
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(WidgetPalette.coral)
                    Spacer(minLength: 0)
                }

                Text(entry.prompt.headline(for: entry.snapshot))
                    .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(family == .systemSmall ? 4 : 3)
                    .minimumScaleFactor(0.85)

                if family == .systemMedium {
                    Text(entry.prompt.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Text(ctaLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var ctaLabel: String {
        let reading = entry.prompt.deepLink == WidgetDeepLink.received
        if family == .systemMedium {
            return reading ? "Read thanks" : "Send thanks"
        }
        return reading ? "Tap to read" : "Tap to write"
    }
}
