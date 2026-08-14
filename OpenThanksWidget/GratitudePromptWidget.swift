import WidgetKit
import SwiftUI

struct GratitudeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let prompt: WidgetPromptKind
    let largeSecondary: WidgetLargeSecondary

    /// Helps Smart Stack / Suggestions surface the widget when there’s something to do.
    var relevance: TimelineEntryRelevance? {
        if snapshot.pendingToAccept > 0 {
            return TimelineEntryRelevance(score: 90, duration: 60 * 60 * 6)
        }
        if snapshot.latestReceived != nil {
            return TimelineEntryRelevance(score: 70, duration: 60 * 60 * 8)
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
        // Widget gallery / Recommended preview — show the engaging monthly copy on medium+.
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
            prompt: WidgetPromptKind.prompt(at: date, snapshot: snapshot, family: family),
            largeSecondary: WidgetLargeSecondary.resolve(at: date, snapshot: snapshot)
        )
    }

    private func previewEntry(for family: WidgetFamily) -> GratitudeEntry {
        let teaser = WidgetReceivedTeaser(
            fromName: "Alex",
            messagePreview: "Thank you for staying late to help me finish that project — I felt so supported.",
            isPending: true
        )
        let snapshot = WidgetSnapshot(
            displayName: nil,
            sentThisMonth: 3,
            receivedTotal: 2,
            pendingToAccept: 1,
            latestReceived: teaser,
            updatedAt: .now
        )
        let prompt: WidgetPromptKind =
            family == .systemSmall ? .whoHelped : .monthlyCount
        return GratitudeEntry(
            date: .now,
            snapshot: snapshot,
            prompt: prompt,
            largeSecondary: .received(teaser)
        )
    }
}

/// Home Screen — rotating gratitude prompts (large size adds a secondary panel).
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
        .description("Rotating prompts — and on the large size, a recent thank-you or reflection.")
        // Medium first so the gallery leads with the fuller, rotating layout.
        .supportedFamilies([
            .systemMedium,
            .systemSmall,
            .systemLarge,
            .systemExtraLarge,
        ])
    }
}

struct GratitudePromptView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GratitudeEntry

    private var isCompact: Bool { family == .systemSmall }
    private var isLarge: Bool {
        family == .systemLarge || family == .systemExtraLarge
    }

    var body: some View {
        if isLarge {
            largeBody
        } else {
            compactBody
        }
    }

    // MARK: Small / medium — single rotating prompt

    private var compactBody: some View {
        Link(destination: entry.prompt.deepLink) {
            VStack(alignment: .leading, spacing: isCompact ? 6 : 10) {
                brandRow

                Text(entry.prompt.headline(for: entry.snapshot))
                    .font(.system(size: headlineSize, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.textPrimary)
                    .lineLimit(isCompact ? 4 : 3)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)

                if !isCompact {
                    Text(entry.prompt.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)

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

    // MARK: Large — prompt on top + received / reflection below

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            brandRow

            Link(destination: entry.prompt.deepLink) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.prompt.headline(for: entry.snapshot))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.prompt.subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(monthlyCountLine)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WidgetPalette.coral)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        Text(entry.prompt.deepLink == WidgetDeepLink.received ? "Read →" : "Thank someone →")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WidgetPalette.coral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }

            secondaryPanel
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var secondaryPanel: some View {
        Link(destination: entry.largeSecondary.deepLink) {
            VStack(alignment: .leading, spacing: 8) {
                switch entry.largeSecondary {
                case .received(let teaser):
                    HStack(spacing: 6) {
                        Image(systemName: teaser.isPending ? "envelope.open.fill" : "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(teaser.isPending ? "Waiting for you" : "Recent appreciation")
                            .font(.system(size: 12, weight: .semibold))
                            .textCase(.uppercase)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(WidgetPalette.coral)

                    Text("From \(teaser.fromName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(1)

                    Text("“\(teaser.messagePreview)”")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(4)
                        .minimumScaleFactor(0.9)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(teaser.isPending ? "Tap to accept →" : "Tap to read →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetPalette.coral)

                case .reflection(let headline, let subtitle):
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Today’s prompt")
                            .font(.system(size: 12, weight: .semibold))
                            .textCase(.uppercase)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(WidgetPalette.coral)

                    Text(headline)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundStyle(WidgetPalette.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(2)

                    Text("Tap to write →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetPalette.coral)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(WidgetPalette.coral.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(WidgetPalette.coral.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
    }

    private var headlineSize: CGFloat {
        if isCompact { return 15 }
        return 17
    }

    private var brandRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.fill")
                .font(.system(size: isLarge ? 13 : 11, weight: .semibold))
                .foregroundStyle(WidgetPalette.coral)
            Text("OpenThanks")
                .font(.system(size: isCompact ? 11 : (isLarge ? 14 : 12), weight: .semibold, design: .rounded))
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
