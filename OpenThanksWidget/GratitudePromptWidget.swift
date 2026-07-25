import WidgetKit
import SwiftUI

struct GratitudeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let prompt: WidgetPromptKind

    /// Helps Smart Stack / Suggestions surface the widget when there’s something to do.
    var relevance: TimelineEntryRelevance? {
        if snapshot.pendingToAccept > 0 {
            return TimelineEntryRelevance(score: 90, duration: 60 * 60 * 6)
        }
        if snapshot.sentThisMonth > 0 {
            return TimelineEntryRelevance(score: 55, duration: 60 * 60 * 12)
        }
        return TimelineEntryRelevance(score: 35)
    }
}

struct GratitudeTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GratitudeEntry {
        previewEntry(for: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (GratitudeEntry) -> Void) {
        // Widget gallery / Recommended preview — show the engaging monthly copy on medium.
        if context.isPreview {
            completion(previewEntry(for: context.family))
            return
        }
        completion(makeEntry(at: .now, family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GratitudeEntry>) -> Void) {
        let now = Date()
        var entries: [GratitudeEntry] = []
        // Rotate every 4 hours so medium/small keep feeling fresh.
        for hourOffset in stride(from: 0, through: 20, by: 4) {
            let date = Calendar.current.date(byAdding: .hour, value: hourOffset, to: now) ?? now
            entries.append(makeEntry(at: date, family: context.family))
        }
        let next = Calendar.current.date(byAdding: .hour, value: 4, to: now)
            ?? now.addingTimeInterval(4 * 3600)
        completion(Timeline(entries: entries, policy: .after(next)))
    }

    private func makeEntry(at date: Date, family: WidgetFamily) -> GratitudeEntry {
        let snapshot = WidgetSnapshotStore.load()
        return GratitudeEntry(
            date: date,
            snapshot: snapshot,
            prompt: WidgetPromptKind.prompt(at: date, snapshot: snapshot, family: family)
        )
    }

    private func previewEntry(for family: WidgetFamily) -> GratitudeEntry {
        let snapshot = WidgetSnapshot(
            displayName: nil,
            sentThisMonth: 3,
            receivedTotal: 2,
            pendingToAccept: 1,
            updatedAt: .now
        )
        let prompt: WidgetPromptKind = family == .systemMedium ? .monthlyCount : .whoHelped
        return GratitudeEntry(date: .now, snapshot: snapshot, prompt: prompt)
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
        .description("Rotating prompts — including how many people you’ve thanked this month.")
        // Medium first so the gallery leads with the fuller, rotating layout.
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}

struct GratitudePromptView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GratitudeEntry

    var body: some View {
        Link(destination: entry.prompt.deepLink) {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                brandRow

                Text(entry.prompt.headline(for: entry.snapshot))
                    .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(family == .systemSmall ? 4 : 3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if family == .systemMedium {
                    Text(entry.prompt.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)

                    // Always keep this month’s count visible while the headline rotates.
                    if entry.prompt != .monthlyCount {
                        Text(monthlyCountLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WidgetPalette.coral)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
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

    private var brandRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.coral)
            Text("OpenThanks")
                .font(.system(size: family == .systemSmall ? 11 : 12, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetPalette.coral)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Spacer(minLength: 0)
        }
    }

    private var monthlyCountLine: String {
        let n = entry.snapshot.sentThisMonth
        if n <= 0 { return "No appreciations sent this month yet" }
        if n == 1 { return "1 appreciation sent this month" }
        return "\(n) appreciations sent this month"
    }

    private var ctaLabel: String {
        let reading = entry.prompt.deepLink == WidgetDeepLink.received
        if family == .systemMedium {
            return reading ? "Read thanks" : "Send thanks"
        }
        return reading ? "Tap to read" : "Tap to write"
    }
}
