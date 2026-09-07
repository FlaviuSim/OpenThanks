import ActivityKit
import SwiftUI
import WidgetKit

struct StreakLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StreakLiveActivityAttributes.self) { context in
            StreakLiveActivityLockScreenView(
                reminderDay: context.attributes.reminderDay,
                state: context.state
            )
            .widgetURL(WidgetDeepLink.compose)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Streak", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.coral)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StreakCountdownText(
                        reminderDay: context.attributes.reminderDay,
                        deadline: context.state.deadline
                    )
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 56, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(expandedTitle(for: context.state))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Link(destination: WidgetDeepLink.compose) {
                        Text("Share a thanks")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(WidgetPalette.coral, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(WidgetPalette.coral)
            } compactTrailing: {
                StreakCountdownText(
                    reminderDay: context.attributes.reminderDay,
                    deadline: context.state.deadline
                )
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(WidgetPalette.coral)
            }
            .widgetURL(WidgetDeepLink.compose)
        }
    }

    private func expandedTitle(for state: StreakLiveActivityAttributes.ContentState) -> String {
        if state.postedToday {
            return "Streak locked in for today"
        }
        let unit = state.streakCount == 1 ? "day" : "days"
        return "Keep your \(state.streakCount)-\(unit) streak"
    }
}

/// Countdown to local midnight. Prefer `timerInterval` over `Text(..., style: .timer)`:
/// once the deadline is in the past, `.timer` counts *up* (elapsed since midnight),
/// which looks like the clock time — the bug Jonny hit.
private struct StreakCountdownText: View {
    let reminderDay: Date
    let deadline: Date

    var body: some View {
        if deadline > reminderDay {
            Text(timerInterval: reminderDay...deadline, countsDown: true, showsHours: true)
        } else {
            Text("0:00")
        }
    }
}

private struct StreakLiveActivityLockScreenView: View {
    let reminderDay: Date
    let state: StreakLiveActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(WidgetPalette.coral.opacity(0.18))
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WidgetPalette.coral)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetPalette.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                StreakCountdownText(reminderDay: reminderDay, deadline: state.deadline)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WidgetPalette.coral)
                    .multilineTextAlignment(.trailing)
                Text("left today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetPalette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(WidgetPalette.background)
        .activitySystemActionForegroundColor(WidgetPalette.coral)
    }

    private var title: String {
        if state.postedToday {
            return "You're set for today"
        }
        let unit = state.streakCount == 1 ? "day" : "days"
        return "Keep your \(state.streakCount)-\(unit) streak"
    }

    private var subtitle: String {
        if state.postedToday {
            return "Come back tomorrow to keep it going"
        }
        return "Send thanks before midnight"
    }
}
