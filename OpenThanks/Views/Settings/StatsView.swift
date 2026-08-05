import SwiftUI

/// Personal gratitude stats: streak hero with accepted progress, month calendar,
/// totals, and an optional remote competition panel.
struct StatsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var activity: [SentActivity] = []
    @State private var profileStats = ProfileStats()
    @State private var competition = CompetitionConfig.disabled
    @State private var pendingSentCount = 0
    @State private var loading = true
    @State private var loadError: String?
    @State private var appearReady = false
    /// End date of the rolling calendar window (inclusive). Defaults to today.
    @State private var rollingWindowEnd = Calendar.current.startOfDay(for: Date())

    private var calendar: Calendar { .current }

    private var rollingWindowDays: Int {
        max(showCompetition ? competition.targetDays : 30, 7)
    }

    private var personalDayDates: [Date] {
        activity.compactMap(\.createdAt)
    }

    private var streakKeep: StreakMath.KeepStatus {
        StreakMath.keepStatus(dates: personalDayDates, calendar: calendar)
    }

    private var currentStreak: Int { streakKeep.streak }

    private var longestStreak: Int {
        StreakMath.longestStreak(
            days: StreakMath.daySet(from: activity, calendar: calendar),
            calendar: calendar
        )
    }

    private var streakAcceptance: (accepted: Int, sent: Int) {
        StreakMath.acceptedDaysInCurrentStreak(posts: activity, calendar: calendar)
    }

    private var competitionProgress: Int {
        guard competition.isActive() || competition.enabled else { return 0 }
        return min(
            StreakMath.competitionCurrentStreak(posts: activity, config: competition, calendar: calendar),
            max(competition.targetDays, 1)
        )
    }

    private var competitionSentStreak: Int {
        guard competition.enabled else { return 0 }
        return min(
            StreakMath.competitionSentStreak(posts: activity, config: competition, calendar: calendar),
            max(competition.targetDays, 1)
        )
    }

    private var showCompetition: Bool {
        competition.enabled
    }

    private var needsAcceptanceNudge: Bool {
        let pair = streakAcceptance
        return pair.sent > 0 && pair.accepted < pair.sent
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
                    calendarSection
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
        let accepted = streakAcceptance.accepted
        let sent = streakAcceptance.sent
        let keep = streakKeep

        return VStack(alignment: .leading, spacing: 18) {
            Text("OpenThanks")
                .font(Theme.body(13, weight: .semibold))
                .foregroundStyle(Theme.coral)

            HStack(alignment: .center, spacing: 18) {
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
                    Text(keep.isActive ? "day streak" : "no streak yet")
                        .font(Theme.display(24, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(streakHeadline(for: keep))
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

            streakKeepBanner(for: keep)

            if sent > 0 {
                acceptanceCard(accepted: accepted, sent: sent)
            }
        }
        .opacity(appearReady ? 1 : 0)
        .offset(y: appearReady ? 0 : 8)
        .animation(.easeOut(duration: 0.45), value: appearReady)
    }

    private func streakHeadline(for keep: StreakMath.KeepStatus) -> String {
        if keep.needsPostToday {
            return "Post once more today to keep your streak going."
        }
        if keep.isSafeToday {
            return "You're set for today — a short note each day keeps it alive."
        }
        return "Share a thanks today to start a streak."
    }

    @ViewBuilder
    private func streakKeepBanner(for keep: StreakMath.KeepStatus) -> some View {
        if keep.needsPostToday {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let remaining = keep.deadline.timeIntervalSince(context.date)
                streakStatusStrip(
                    icon: remaining <= 3 * 3600 ? "flame.fill" : "clock.fill",
                    title: remaining > 0
                        ? "\(StreakDeadlineFormatting.remaining(remaining)) left to keep it"
                        : "Streak ends at midnight — post now",
                    detail: "Send any appreciation before midnight (\(StreakDeadlineFormatting.midnightLabel(keep.deadline))).",
                    emphasizesUrgency: remaining > 0 && remaining <= 3 * 3600,
                    showCompose: true
                )
            }
        } else if keep.isSafeToday {
            streakStatusStrip(
                icon: "checkmark.circle.fill",
                title: "Posted today — streak locked in",
                detail: "Send another thanks tomorrow before midnight to keep it going.",
                emphasizesUrgency: false,
                showCompose: false
            )
        } else {
            streakStatusStrip(
                icon: "sparkles",
                title: "Start a streak today",
                detail: "Post before midnight to begin counting consecutive days.",
                emphasizesUrgency: false,
                showCompose: true
            )
        }
    }

    private func streakStatusStrip(
        icon: String,
        title: String,
        detail: String,
        emphasizesUrgency: Bool,
        showCompose: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(emphasizesUrgency ? Theme.coral : Theme.coralLight)
                    .frame(width: 22, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.opacity)
                    Text(detail)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if showCompose {
                Button {
                    ComposeLaunchBridge.shared.queue(analyticsSource: "stats_streak_keep")
                    dismiss()
                } label: {
                    Text(emphasizesUrgency || streakKeep.needsPostToday ? "Share a thanks now" : "Share a thanks")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.ctaGradient, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(emphasizesUrgency ? Theme.coral.opacity(0.12) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    emphasizesUrgency ? Theme.coral.opacity(0.35) : Theme.hairline,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
    }

    private func acceptanceCard(accepted: Int, sent: Int) -> some View {
        let complete = accepted == sent
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(accepted)")
                    .font(Theme.display(28, weight: .semibold))
                    .foregroundStyle(complete ? Theme.coral : Theme.textPrimary)
                    .contentTransition(.numericText())
                Text("of \(sent) accepted")
                    .font(Theme.body(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                if complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.coral)
                        .font(.system(size: 20, weight: .semibold))
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                    Capsule()
                        .fill(Theme.coral)
                        .frame(
                            width: appearReady
                                ? geo.size.width * CGFloat(accepted) / CGFloat(max(sent, 1))
                                : 0
                        )
                        .animation(.easeOut(duration: 0.8).delay(0.15), value: appearReady)
                }
            }
            .frame(height: 8)

            Text(
                complete
                    ? "Every day in your streak has been accepted — beautiful."
                    : "Your streak counts the days you send. Unlock the classroom gift when those appreciations are accepted."
            )
            .font(Theme.body(13))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if needsAcceptanceNudge {
                NavigationLink {
                    PendingAppreciationsView()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge")
                            .font(.system(size: 14, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nudge Pending Appreciations")
                                .font(Theme.body(14, weight: .semibold))
                            Text(
                                pendingSentCount > 0
                                    ? "\(pendingSentCount) waiting — send a reminder to accept"
                                    : "Remind recipients so these days can count"
                            )
                            .font(Theme.body(12))
                            .opacity(0.85)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.ctaGradient)
                    )
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
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var ringProgress: CGFloat {
        if showCompetition, competition.targetDays > 0 {
            return CGFloat(competitionProgress) / CGFloat(competition.targetDays)
        }
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

            if !competition.isActive() {
                Text("This challenge isn’t active right now.")
                    .font(Theme.body(12, weight: .medium))
                    .foregroundStyle(Theme.coral)
            }

            VStack(alignment: .leading, spacing: 10) {
                competitionMetricRow(
                    title: "Sent streak",
                    value: "\(competitionSentStreak) of \(competition.targetDays)",
                    detail: "Days in a row you posted",
                    progress: Double(competitionSentStreak),
                    total: Double(max(competition.targetDays, 1)),
                    tint: Theme.coralLight
                )
                competitionMetricRow(
                    title: "Accepted streak",
                    value: "\(competitionProgress) of \(competition.targetDays)",
                    detail: "Days that unlock the classroom gift",
                    progress: Double(competitionProgress),
                    total: Double(max(competition.targetDays, 1)),
                    tint: Theme.coral
                )
            }

            Text("Start anytime. Build any rolling streak of \(competition.targetDays) days in a row — not tied to a calendar month. Finishers unlock $30 to give away to a classroom once each of those days has an accepted appreciation.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if competition.requireAccepted, competitionSentStreak > competitionProgress {
                NavigationLink {
                    PendingAppreciationsView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.clipboard")
                        Text("Open Pending Appreciations")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.coral.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }

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

    private func competitionMetricRow(
        title: String,
        value: String,
        detail: String,
        progress: Double,
        total: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(value)
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ProgressView(value: progress, total: total)
                .tint(tint)
            Text(detail)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(showCompetition ? "Rolling \(rollingWindowDays) days" : "Your rhythm")
                .font(Theme.display(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(
                showCompetition
                    ? "A moving \(rollingWindowDays)-day window — not a calendar month. Solid days are accepted; soft days are still pending."
                    : "Each day you share appreciation. Solid days are accepted; soft days are still pending."
            )
            .font(Theme.body(13))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            ActivityCalendarView(
                posts: activity,
                windowDays: rollingWindowDays,
                windowEnd: $rollingWindowEnd,
                appear: appearReady
            )

            HStack(spacing: 14) {
                legendSwatch(color: Theme.coral, label: "Accepted")
                legendSwatch(color: Theme.coral.opacity(0.28), label: "Sent · pending", stroked: true)
                legendSwatch(color: Theme.surfaceRaised, label: "No post")
            }
            .font(Theme.body(11))
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private func legendSwatch(color: Color, label: String, stroked: Bool = false) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .overlay {
                    if stroked {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Theme.coral.opacity(0.55), lineWidth: 1)
                    }
                }
                .frame(width: 12, height: 12)
            Text(label)
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
            async let pendingTask = GratitudeService.pendingCount(authorId: userId)

            let (config, rows, stats, pending) = try await (configTask, activityTask, statsTask, pendingTask)
            competition = config
            pendingSentCount = pending
            // Rolling challenge: load enough history for a long streak (ignore month windows).
            let lookbackDays = max(config.targetDays * 3, 120)
            let rollingSince = calendar.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? since
            if rollingSince < since {
                activity = try await GratitudeService.sentActivity(authorId: userId, since: rollingSince)
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

// MARK: - Rolling calendar window

private struct ActivityCalendarView: View {
    let posts: [SentActivity]
    let windowDays: Int
    @Binding var windowEnd: Date
    let appear: Bool

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var today: Date { calendar.startOfDay(for: Date()) }

    private var windowStart: Date {
        calendar.date(byAdding: .day, value: -(max(windowDays, 1) - 1), to: windowEnd) ?? windowEnd
    }

    private var windowTitle: String {
        let startLabel = windowStart.formatted(.dateTime.month(.abbreviated).day())
        let endLabel = windowEnd.formatted(.dateTime.month(.abbreviated).day())
        if calendar.isDate(windowEnd, inSameDayAs: today) {
            return "Last \(windowDays) days"
        }
        return "\(startLabel) – \(endLabel)"
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var daysInGrid: [Date?] {
        let weekday = calendar.component(.weekday, from: windowStart)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<max(windowDays, 1) {
            if let date = calendar.date(byAdding: .day, value: offset, to: windowStart) {
                cells.append(date)
            }
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    private var canGoForward: Bool {
        windowEnd < today
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        windowEnd = calendar.date(byAdding: .day, value: -windowDays, to: windowEnd) ?? windowEnd
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Earlier \(windowDays) days")

                Spacer()
                Text(windowTitle)
                    .font(Theme.display(18, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                Spacer()

                Button {
                    guard canGoForward else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        let next = calendar.date(byAdding: .day, value: windowDays, to: windowEnd) ?? windowEnd
                        windowEnd = min(next, today)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canGoForward ? Theme.textSecondary : Theme.textTertiary.opacity(0.35))
                        .frame(width: 36, height: 36)
                        .background(Theme.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .accessibilityLabel("Later \(windowDays) days")
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(Theme.body(11, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 2)
                }

                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { index, day in
                    if let day {
                        dayCell(day, index: index)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func dayCell(_ day: Date, index: Int) -> some View {
        let kind = StreakMath.activity(on: day, posts: posts, calendar: calendar)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > today
        let number = calendar.component(.day, from: day)

        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(fill(for: kind, isFuture: isFuture))
                .overlay {
                    if kind == .pending {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.coral.opacity(0.45), lineWidth: 1)
                    }
                    if isToday {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.coral, lineWidth: 1.5)
                    }
                }

            Text("\(number)")
                .font(Theme.body(13, weight: isToday || kind != .empty ? .semibold : .regular))
                .foregroundStyle(foreground(for: kind, isFuture: isFuture))
        }
        .frame(height: 40)
        .opacity(appear ? (isFuture ? 0.35 : 1) : 0)
        .scaleEffect(appear ? 1 : 0.92)
        .animation(
            .easeOut(duration: 0.35).delay(Double(index % 14) * 0.015),
            value: appear
        )
        .accessibilityLabel(accessibilityLabel(day: day, kind: kind))
    }

    private func fill(for kind: StreakMath.DayActivity, isFuture: Bool) -> Color {
        if isFuture { return Theme.surfaceRaised.opacity(0.4) }
        switch kind {
        case .empty: return Theme.surfaceRaised
        case .pending: return Theme.coral.opacity(0.18)
        case .accepted: return Theme.coral
        }
    }

    private func foreground(for kind: StreakMath.DayActivity, isFuture: Bool) -> Color {
        if isFuture { return Theme.textTertiary }
        switch kind {
        case .empty: return Theme.textSecondary
        case .pending: return Theme.coral
        case .accepted: return .white
        }
    }

    private func accessibilityLabel(day: Date, kind: StreakMath.DayActivity) -> String {
        let date = day.formatted(.dateTime.month(.abbreviated).day())
        switch kind {
        case .empty: return "\(date), no appreciation"
        case .pending: return "\(date), sent, awaiting acceptance"
        case .accepted: return "\(date), accepted"
        }
    }
}

// MARK: - Streak deadline copy

private enum StreakDeadlineFormatting {
    /// Human remaining time until local midnight (e.g. "6h 42m", "45m", "under a minute").
    static func remaining(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 1 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes >= 1 {
            return "\(minutes)m"
        }
        return "under a minute"
    }

    /// Local midnight label for the streak deadline (start of tomorrow).
    static func midnightLabel(_ deadline: Date) -> String {
        deadline.formatted(date: .omitted, time: .shortened)
    }
}
