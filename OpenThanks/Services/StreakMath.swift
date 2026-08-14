import Foundation

/// Remote competition campaign decoded from `app_config` key `competition`.
struct CompetitionConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var id: String
    var title: String
    var subtitle: String
    var prizeLabel: String
    var targetDays: Int
    /// Optional bounds for a limited campaign. For the rolling 30-day challenge,
    /// leave both `nil` so streaks can start anytime while the challenge is enabled.
    var startsAt: Date?
    var endsAt: Date?
    var allowedSources: [String]
    var requireAccepted: Bool
    var requireOtherRecipient: Bool
    var termsUrl: String
    var rulesSummary: [String]
    var winnerNotifyBody: String

    static let disabled = CompetitionConfig(
        enabled: false,
        id: "",
        title: "",
        subtitle: "",
        prizeLabel: "",
        targetDays: 30,
        startsAt: nil,
        endsAt: nil,
        allowedSources: ["ios", "watch"],
        requireAccepted: false,
        requireOtherRecipient: true,
        termsUrl: "https://openthanks.com/competition",
        rulesSummary: [],
        winnerNotifyBody: "You finished the challenge! We'll follow up with how to unlock your $30 classroom gift."
    )

    var termsURL: URL? {
        URL(string: termsUrl)
    }

    func isActive(at date: Date = .now) -> Bool {
        guard enabled else { return false }
        if let startsAt, date < startsAt { return false }
        if let endsAt, date >= endsAt { return false }
        return true
    }
}

/// Lightweight sent-post row for streak / competition math.
struct SentActivity: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date?
    let source: String?
    let status: GratitudeStatus?
    let recipientId: UUID?
    let authorId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case source
        case status
        case recipientId = "recipient_id"
        case authorId = "author_id"
    }
}

/// Pure calendar-day streak helpers (local timezone by default).
enum StreakMath {
    /// Whether today's send is already in, and when the streak resets if it isn't.
    ///
    /// Streaks are calendar-day based with a one-day grace: posting yesterday still
    /// keeps the streak alive until **local midnight tonight**. After that, it resets.
    struct KeepStatus: Equatable, Sendable {
        let streak: Int
        let postedToday: Bool
        /// Start of tomorrow in `calendar` — the moment an unposted streak becomes 0.
        let deadline: Date

        var isActive: Bool { streak > 0 }
        /// On a streak but haven't sent yet today — must post before `deadline`.
        var needsPostToday: Bool { streak > 0 && !postedToday }
        /// On a streak and already sent today — safe until tomorrow.
        var isSafeToday: Bool { streak > 0 && postedToday }
    }

    /// Snapshot of streak keep-alive state for UI (countdown, copy).
    static func keepStatus(
        dates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> KeepStatus {
        let streak = currentStreak(dates: dates, calendar: calendar, now: now)
        let today = calendar.startOfDay(for: now)
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let postedToday = days.contains(today)
        let deadline = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return KeepStatus(streak: streak, postedToday: postedToday, deadline: deadline)
    }

    /// Consecutive calendar days ending today or yesterday with ≥1 post.
    static func currentStreak(
        dates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    /// Longest run of consecutive days in `days` (already normalized to start-of-day).
    static func longestStreak(days: Set<Date>, calendar: Calendar = .current) -> Int {
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1
        var run = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let cur = sorted[i]
            if let expected = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(expected, inSameDayAs: cur) {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    /// Posts that count toward the remote competition (accepted / payout streak).
    static func competitionEligiblePosts(
        _ posts: [SentActivity],
        config: CompetitionConfig,
        now: Date = .now
    ) -> [SentActivity] {
        guard config.enabled else { return [] }
        let allowed = Set(config.allowedSources.map { $0.lowercased() })
        return posts.filter { post in
            guard let created = post.createdAt else { return false }
            if let start = config.startsAt, created < start { return false }
            if let end = config.endsAt, created >= end { return false }
            guard allowed.contains(normalizedSource(post.source)) else { return false }
            if config.requireOtherRecipient {
                guard let recipientId = post.recipientId else { return false }
                if let authorId = post.authorId, recipientId == authorId { return false }
            }
            if config.requireAccepted {
                guard post.status == .accepted else { return false }
            }
            return true
        }
    }

    /// Posts that count toward the challenge *send* streak (posted in-window from an
    /// allowed channel). Does not require acceptance or a linked recipient yet —
    /// those gate the payout / accepted streak instead.
    static func competitionSentPosts(
        _ posts: [SentActivity],
        config: CompetitionConfig,
        now: Date = .now
    ) -> [SentActivity] {
        guard config.enabled else { return [] }
        let allowed = Set(config.allowedSources.map { $0.lowercased() })
        return posts.filter { post in
            guard let created = post.createdAt else { return false }
            if let start = config.startsAt, created < start { return false }
            if let end = config.endsAt, created >= end { return false }
            return allowed.contains(normalizedSource(post.source))
        }
    }

    /// Legacy rows often have `source = null`; treat those as iOS when iOS is allowed.
    static func normalizedSource(_ source: String?) -> String {
        let trimmed = (source ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trimmed.isEmpty ? "ios" : trimmed
    }

    static func daySet(
        from posts: [SentActivity],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(posts.compactMap { post -> Date? in
            guard let created = post.createdAt else { return nil }
            return calendar.startOfDay(for: created)
        })
    }

    /// Current competition streak (consecutive eligible days ending today/yesterday).
    static func competitionCurrentStreak(
        posts: [SentActivity],
        config: CompetitionConfig,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let eligible = competitionEligiblePosts(posts, config: config, now: now)
        let days = daySet(from: eligible, calendar: calendar)
        return currentStreak(dates: Array(days), calendar: calendar, now: now)
    }

    /// Consecutive days posted toward the challenge (send streak), ignoring acceptance.
    static func competitionSentStreak(
        posts: [SentActivity],
        config: CompetitionConfig,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let sent = competitionSentPosts(posts, config: config, now: now)
        let days = daySet(from: sent, calendar: calendar)
        return currentStreak(dates: Array(days), calendar: calendar, now: now)
    }

    /// Distinct eligible days toward the prize (capped display uses min with target).
    static func competitionEligibleDayCount(
        posts: [SentActivity],
        config: CompetitionConfig,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        daySet(
            from: competitionEligiblePosts(posts, config: config, now: now),
            calendar: calendar
        ).count
    }

    /// Counts per day for heatmap intensity.
    static func postsPerDay(
        posts: [SentActivity],
        calendar: Calendar = .current
    ) -> [Date: Int] {
        var map: [Date: Int] = [:]
        for post in posts {
            guard let created = post.createdAt else { continue }
            let day = calendar.startOfDay(for: created)
            map[day, default: 0] += 1
        }
        return map
    }

    /// Start-of-day dates that make up the current personal streak (empty if streak is 0).
    static func currentStreakDays(
        dates: [Date],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Set<Date> {
        let streak = currentStreak(dates: dates, calendar: calendar, now: now)
        guard streak > 0 else { return [] }

        let days = Set(dates.map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return []
        }

        var result = Set<Date>()
        for _ in 0..<streak {
            result.insert(cursor)
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return result
    }

    /// Days that have at least one accepted appreciation.
    static func acceptedDaySet(
        from posts: [SentActivity],
        calendar: Calendar = .current
    ) -> Set<Date> {
        daySet(
            from: posts.filter { $0.status == .accepted },
            calendar: calendar
        )
    }

    /// Days that have only pending (or rejected) sends — no accepted post yet.
    static func pendingOnlyDaySet(
        from posts: [SentActivity],
        calendar: Calendar = .current
    ) -> Set<Date> {
        let accepted = acceptedDaySet(from: posts, calendar: calendar)
        let all = daySet(from: posts, calendar: calendar)
        return all.subtracting(accepted)
    }

    /// Within the current send streak, how many of those days already have an accepted post.
    static func acceptedDaysInCurrentStreak(
        posts: [SentActivity],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> (accepted: Int, sent: Int) {
        let dates = posts.compactMap(\.createdAt)
        let streakDays = currentStreakDays(dates: dates, calendar: calendar, now: now)
        let accepted = acceptedDaySet(from: posts, calendar: calendar)
        let acceptedCount = streakDays.intersection(accepted).count
        return (acceptedCount, streakDays.count)
    }

    enum DayActivity: Equatable {
        case empty
        case pending
        case accepted
    }

    /// Best status for a calendar day: accepted wins over pending.
    static func activity(
        on day: Date,
        posts: [SentActivity],
        calendar: Calendar = .current
    ) -> DayActivity {
        let start = calendar.startOfDay(for: day)
        var sawPending = false
        for post in posts {
            guard let created = post.createdAt,
                  calendar.isDate(created, inSameDayAs: start)
            else { continue }
            if post.status == .accepted { return .accepted }
            if post.status == .pending { sawPending = true }
        }
        return sawPending ? .pending : .empty
    }
}
