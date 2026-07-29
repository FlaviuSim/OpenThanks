import Foundation

/// Remote competition campaign decoded from `app_config` key `competition`.
struct CompetitionConfig: Codable, Equatable, Sendable {
    var enabled: Bool
    var id: String
    var title: String
    var subtitle: String
    var prizeLabel: String
    var targetDays: Int
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
        requireAccepted: true,
        requireOtherRecipient: true,
        termsUrl: "https://openthanks.com/competition",
        rulesSummary: [],
        winnerNotifyBody: "You completed the competition! We'll follow up with how to receive your prize."
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

    /// Posts that count toward the remote competition.
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
            let source = (post.source ?? "").lowercased()
            guard allowed.contains(source) else { return false }
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
}
