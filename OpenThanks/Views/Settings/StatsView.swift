import SwiftUI

/// Personal gratitude stats: streak hero, activity heatmap, totals,
/// and an optional remote competition panel.
struct StatsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var activity: [SentActivity] = []
    @State private var profileStats = ProfileStats()
    @State private var competition = CompetitionConfig.disabled
    @State private var loading = true
    @State private var loadError: String?
    @State private var appearReady = false

    private var calendar: Calendar { .current }

    private var personalDayDates: [Date] {
        activity.compactMap(\.createdAt)
    }

    private var currentStreak: Int {
        StreakMath.currentStreak(dates: personalDayDates, calendar: calendar)
    }

    private var longestStreak: Int {
        StreakMath.longestStreak(
            days: StreakMath.daySet(from: activity, calendar: calendar),
            calendar: calendar
        )
    }

    private var postsPerDay: [Date: Int] {
        StreakMath.postsPerDay(posts: activity, calendar: calendar)
    }

    private var competitionProgress: Int {
        guard competition.isActive() || competition.enabled else { return 0 }
        return min(
            StreakMath.competitionCurrentStreak(posts: activity, config: competition, calendar: calendar),
            max(competition.targetDays, 1)
        )
    }

    private var showCompetition: Bool {
        competition.enabled
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if loading {
                    ProgressView()
                        .tint(Theme.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let loadError {
                    Text(loadError)
                        .font(Theme.body(14))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                } else {
                    streakHero
                    if showCompetition {
                        competitionPanel
                    }
                    heatmapSection
                    totalsSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .tabChromeBottomPadding()
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Your Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Hero

    private var streakHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenThanks")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.coral)

            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Theme.hairline, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: appearReady ? ringProgress : 0)
                        .stroke(
                            Theme.coral,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.9), value: appearReady)

                    VStack(spacing: 2) {
                        Text("\(currentStreak)")
                            .font(Theme.display(44, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text(currentStreak == 1 ? "day" : "days")
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    Text("in a row")
                        .font(Theme.display(26, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(
                        currentStreak == 0
                            ? "Share a thanks today to start a streak."
                            : "Keep showing up — a short note is enough."
                    )
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if longestStreak > currentStreak {
                        Text("Best streak: \(longestStreak) days")
                            .font(Theme.body(12, weight: .medium))
                            .foregroundStyle(Theme.coral)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .opacity(appearReady ? 1 : 0)
        .offset(y: appearReady ? 0 : 8)
        .animation(.easeOut(duration: 0.45), value: appearReady)
    }

    private var ringProgress: CGFloat {
        if showCompetition, competition.targetDays > 0 {
            return CGFloat(competitionProgress) / CGFloat(competition.targetDays)
        }
        // Soft personal ring: saturates around two weeks.
        return min(CGFloat(currentStreak) / 14, 1)
    }

    // MARK: - Competition

    private var competitionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(competition.title)
                        .font(Theme.display(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(competition.subtitle)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(competition.prizeLabel)
                    .font(Theme.display(28, weight: .semibold))
                    .foregroundStyle(Theme.coral)
            }

            ProgressView(
                value: Double(competitionProgress),
                total: Double(max(competition.targetDays, 1))
            )
            .tint(Theme.coral)

            Text("\(competitionProgress) of \(competition.targetDays) days")
                .font(Theme.body(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            if !competition.rulesSummary.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(competition.rulesSummary.enumerated()), id: \.offset) { _, rule in
                        HStack(alignment: .top, spacing: 8) {
                            Text("·")
                                .foregroundStyle(Theme.coral)
                            Text(rule)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }

            HStack(spacing: 12) {
                if let url = competition.termsURL {
                    Link("Full terms", destination: url)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                }
                Spacer()
                Button {
                    ComposeLaunchBridge.shared.queue(analyticsSource: "stats_competition")
                    dismiss()
                } label: {
                    Text("Share a thanks")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.coral, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.coral.opacity(0.25), lineWidth: 1)
        )
        .opacity(appearReady ? 1 : 0)
        .animation(.easeOut(duration: 0.55).delay(0.08), value: appearReady)
    }

    // MARK: - Heatmap

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your rhythm")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Days you shared appreciation.")
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)

            ActivityHeatmapView(
                postsPerDay: postsPerDay,
                weeks: 14,
                appear: appearReady
            )
        }
    }

    // MARK: - Totals

    private var totalsSection: some View {
        HStack(spacing: 0) {
            totalCell(value: profileStats.sent, label: "Sent")
            Divider().frame(height: 36)
            totalCell(value: profileStats.received, label: "Received")
            Divider().frame(height: 36)
            totalCell(value: profileStats.inspired, label: "Inspired")
        }
        .padding(.vertical, 8)
        .opacity(appearReady ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.15), value: appearReady)
    }

    private func totalCell(value: Int, label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }

        guard case .signedIn(let userId) = auth.state else {
            loadError = "Sign in to see your stats."
            return
        }

        let since = calendar.date(byAdding: .day, value: -120, to: Date()) ?? Date()

        do {
            async let configTask = CompetitionConfigService.refresh(force: true)
            async let activityTask = GratitudeService.sentActivity(authorId: userId, since: since)
            async let statsTask = GratitudeService.stats(userId: userId)

            let (config, rows, stats) = try await (configTask, activityTask, statsTask)
            competition = config
            // If competition starts earlier than 120 days, extend fetch.
            if let start = config.startsAt, start < since {
                activity = try await GratitudeService.sentActivity(authorId: userId, since: start)
            } else {
                activity = rows
            }
            profileStats = stats
            appearReady = true
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Heatmap

private struct ActivityHeatmapView: View {
    let postsPerDay: [Date: Int]
    let weeks: Int
    let appear: Bool

    private let calendar = Calendar.current
    private let cell: CGFloat = 11
    private let gap: CGFloat = 3

    private var columns: [[Date]] {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) // 1=Sun
        let daysFromWeekStart = weekday - calendar.firstWeekday
        let adjusted = (daysFromWeekStart + 7) % 7
        guard let endOfWeek = calendar.date(byAdding: .day, value: 6 - adjusted, to: today),
              let start = calendar.date(byAdding: .day, value: -(weeks * 7 - 1), to: endOfWeek)
        else { return [] }

        var result: [[Date]] = []
        var cursor = start
        for _ in 0..<weeks {
            var week: [Date] = []
            for _ in 0..<7 {
                week.append(cursor)
                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            result.append(week)
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(columns.enumerated()), id: \.offset) { weekIndex, week in
                    VStack(spacing: gap) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(color(for: day))
                                .frame(width: cell, height: cell)
                                .opacity(appear ? 1 : 0)
                                .animation(
                                    .easeOut(duration: 0.35).delay(Double(weekIndex) * 0.02),
                                    value: appear
                                )
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for day: Date) -> Color {
        let count = postsPerDay[calendar.startOfDay(for: day)] ?? 0
        switch count {
        case 0: return Theme.surfaceRaised
        case 1: return Theme.coral.opacity(0.35)
        case 2: return Theme.coral.opacity(0.6)
        default: return Theme.coral
        }
    }
}
