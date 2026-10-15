import Foundation
import Observation

/// One day from the remote campaign feed.
struct CampaignPrompt: Codable, Equatable, Sendable, Identifiable {
    var day: Int
    var date: String
    var theme: String?
    var prompt: String
    var example: String?

    var id: Int { day }
}

/// `{ id, title, start, end, timezone, prompts: [{ day, date, theme, prompt, example }] }`
/// from `https://openthanks.com/campaigns/november-2026.json`.
struct CampaignFeed: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var start: String
    var end: String
    var timezone: String
    var prompts: [CampaignPrompt]

    static let november2026ID = "november-2026"
    static let cardTitle = "30 Days of Thanks"
    static let fallbackTimeZoneID = "America/New_York"
    static let jsonURL = URL(string: "https://openthanks.com/campaigns/november-2026.json")!
    static let apiURL = URL(string: "https://openthanks.com/api/campaigns/november-2026")!

    var timeZone: TimeZone {
        TimeZone(identifier: timezone) ?? TimeZone(identifier: Self.fallbackTimeZoneID)!
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    var windowStart: Date? {
        Self.date(ymd: start, timeZone: timeZone, hour: 0)
    }

    var windowEnd: Date? {
        Self.date(ymd: end, timeZone: timeZone, hour: 0)
    }

    /// Inclusive length of start...end in the feed timezone (November is 30).
    var inclusiveDayCount: Int {
        guard let startDate = windowStart, let endDate = windowEnd else {
            return max(prompts.count, 1)
        }
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(days + 1, 1)
    }

    func ymd(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    func contains(ymd: String) -> Bool {
        guard let startKey = Self.normalizeYMD(start),
              let endKey = Self.normalizeYMD(end),
              let dayKey = Self.normalizeYMD(ymd)
        else { return false }
        return dayKey >= startKey && dayKey <= endKey
    }

    func prompt(on date: Date) -> CampaignPrompt? {
        prompt(onYMD: ymd(for: date))
    }

    func prompt(onYMD ymd: String) -> CampaignPrompt? {
        guard let key = Self.normalizeYMD(ymd), contains(ymd: key) else { return nil }
        return prompts.first { Self.normalizeYMD($0.date) == key }
    }

    func prompt(day: Int) -> CampaignPrompt? {
        prompts.first { $0.day == day }
    }

    static func normalizeYMD(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let prefix = String(trimmed.prefix(10))
        let parts = prefix.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              Int(parts[0]) != nil,
              let month = Int(parts[1]), (1...12).contains(month),
              let day = Int(parts[2]), (1...31).contains(day)
        else { return nil }
        return prefix
    }

    static func date(ymd: String, timeZone: TimeZone, hour: Int) -> Date? {
        guard let key = normalizeYMD(ymd) else { return nil }
        let parts = key.split(separator: "-")
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
    }

    init(id: String, title: String, start: String, end: String, timezone: String, prompts: [CampaignPrompt]) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.timezone = timezone
        self.prompts = prompts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.cardTitle
        start = try container.decode(String.self, forKey: .start)
        end = try container.decode(String.self, forKey: .end)
        let zone = try container.decodeIfPresent(String.self, forKey: .timezone)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        timezone = (zone?.isEmpty == false) ? zone! : Self.fallbackTimeZoneID
        prompts = try container.decode([CampaignPrompt].self, forKey: .prompts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(prompts, forKey: .prompts)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, start, end, timezone, prompts
    }
}

/// Lock-protected feed so reminder scheduling can read today's prompt off the main actor.
final class CampaignFeedCache: @unchecked Sendable {
    static let shared = CampaignFeedCache()

    private let lock = NSLock()
    private var feed: CampaignFeed?

    func current() -> CampaignFeed? {
        lock.lock()
        defer { lock.unlock() }
        return feed
    }

    func update(_ feed: CampaignFeed?) {
        lock.lock()
        self.feed = feed
        lock.unlock()
    }

    func prompt(on date: Date) -> CampaignPrompt? {
        current()?.prompt(on: date)
    }
}

/// Fetches the November campaign in the background, caches it on disk, and
/// exposes today's prompt. Never required for launch or compose.
@MainActor
@Observable
final class CampaignService {
    static let shared = CampaignService()

    private static let freshInterval: TimeInterval = 60 * 60
    #if DEBUG
    private static let debugDateKey = "campaign.debugDateYMD.v1"
    #endif

    private(set) var feed: CampaignFeed?
    /// Distinct days the signed-in user sent during the window. Nil until loaded.
    private(set) var daysSent: Int?
    #if DEBUG
    /// yyyy-MM-dd stand-in for "today". Release builds ignore this.
    private(set) var debugDateYMD: String?
    #endif

    private var sentDayKeys: Set<String> = []
    private var progressLoaded = false
    private var lastRevalidatedAt: Date?
    private var refreshTask: Task<Void, Never>?

    private init() {
        if let disk = Self.loadDisk() {
            apply(disk.feed, persist: false)
            lastRevalidatedAt = disk.savedAt
        }
        #if DEBUG
        if let stored = UserDefaults.standard.string(forKey: Self.debugDateKey) {
            debugDateYMD = CampaignFeed.normalizeYMD(stored)
        }
        #endif
    }

    var todayPrompt: CampaignPrompt? {
        promptForUI()
    }

    var progressTotal: Int {
        feed?.inclusiveDayCount ?? 30
    }

    /// Prompt for the UI clock: the debug override in DEBUG, otherwise now.
    func promptForUI(at date: Date = Date()) -> CampaignPrompt? {
        guard let feed else { return nil }
        #if DEBUG
        if let debugDateYMD {
            return feed.prompt(onYMD: debugDateYMD)
        }
        #endif
        return feed.prompt(on: date)
    }

    /// Background refresh. Concurrent callers share one in-flight request.
    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        let task = Task { @MainActor in
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
        if refreshTask == task {
            refreshTask = nil
        }
    }

    /// Same lightweight sent-activity query streaks already use. No feed-sized select.
    func refreshProgress(authorId: UUID) async {
        guard let feed, todayPrompt != nil, let start = feed.windowStart, let end = feed.windowEnd else {
            daysSent = nil
            sentDayKeys = []
            progressLoaded = false
            return
        }
        do {
            let rows = try await GratitudeService.sentActivity(authorId: authorId, since: start, limit: 400)
            let dates = rows.compactMap(\.createdAt)
            let days = StreakMath.distinctSendDays(dates: dates, from: start, through: end, calendar: feed.calendar)
            sentDayKeys = Set(days.map { feed.ymd(for: $0) })
            daysSent = sentDayKeys.count
            progressLoaded = true
        } catch {
            // Keep the last count when the streak query fails offline.
        }
    }

    /// Optimistic +1 when a send lands on a campaign day we had not counted yet.
    func noteSent(at date: Date) {
        guard progressLoaded, let feed else { return }
        let key = feed.ymd(for: date)
        guard feed.contains(ymd: key) else { return }
        guard sentDayKeys.insert(key).inserted else { return }
        daysSent = sentDayKeys.count
    }

    func openCompose(prompt: CampaignPrompt, analyticsSource: String) {
        guard let feed else { return }
        let text = prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        ComposeLaunchBridge.shared.queue(
            campaignHint: text,
            campaignId: feed.id,
            campaignDay: prompt.day,
            analyticsSource: analyticsSource
        )
    }

    /// Deep link / universal link. The form opens immediately from the cached feed.
    /// Waiting on the network before queueing dropped the launch on cold start
    /// (the cover never appeared, so `appreciation_form_started` never fired).
    /// Campaign props are attached only when a prompt is already resolved.
    func openCompose(link: CampaignComposeLink, analyticsSource: String) async {
        let match = feed == nil ? nil : resolvedPrompt(for: link)
        let hint = match?.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        ComposeLaunchBridge.shared.queue(
            campaignHint: (hint?.isEmpty == false) ? hint : nil,
            campaignId: match == nil ? nil : link.id,
            campaignDay: match?.day,
            analyticsSource: analyticsSource
        )
        if feed == nil {
            await refresh()
        }
    }

    #if DEBUG
    func setDebugDate(_ date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let ymd = String(format: "%04d-%02d-%02d", year, month, day)
        debugDateYMD = CampaignFeed.normalizeYMD(ymd)
        if let debugDateYMD {
            UserDefaults.standard.set(debugDateYMD, forKey: Self.debugDateKey)
        }
    }

    func clearDebugDate() {
        debugDateYMD = nil
        UserDefaults.standard.removeObject(forKey: Self.debugDateKey)
    }

    static func debugPreviewStart() -> Date {
        CampaignFeed.date(
            ymd: "2026-11-01",
            timeZone: TimeZone(identifier: CampaignFeed.fallbackTimeZoneID) ?? .current,
            hour: 12
        ) ?? Date()
    }
    #endif

    // MARK: - Refresh

    private func performRefresh() async {
        let current = feed
        guard shouldRevalidate(current) else { return }

        let cached = Self.loadDisk()
        let urls = [CampaignFeed.jsonURL, CampaignFeed.apiURL]
        for url in urls {
            let etag = (cached?.source == url.absoluteString) ? cached?.etag : nil
            switch await Self.fetch(url, etag: etag) {
            case .notModified:
                lastRevalidatedAt = Date()
                if let current {
                    Self.saveDisk(current, etag: cached?.etag, source: url.absoluteString)
                }
                return
            case .updated(let decoded, let etag):
                guard let clean = Self.sanitized(decoded) else { continue }
                apply(clean, persist: true, etag: etag, source: url.absoluteString)
                lastRevalidatedAt = Date()
                return
            case .failed:
                continue
            }
        }
    }

    private func shouldRevalidate(_ feed: CampaignFeed?) -> Bool {
        guard let lastRevalidatedAt else { return true }
        if Date().timeIntervalSince(lastRevalidatedAt) > Self.freshInterval { return true }
        if let feed, feed.ymd(for: lastRevalidatedAt) != feed.ymd(for: Date()) { return true }
        return false
    }

    private func resolvedPrompt(for link: CampaignComposeLink) -> CampaignPrompt? {
        guard let feed, feed.id == link.id else { return nil }
        if let day = link.day {
            return feed.prompt(day: day)
        }
        return promptForUI()
    }

    private func apply(
        _ feed: CampaignFeed,
        persist: Bool,
        etag: String? = nil,
        source: String? = nil
    ) {
        self.feed = feed
        CampaignFeedCache.shared.update(feed)
        if persist {
            Self.saveDisk(feed, etag: etag, source: source)
        }
    }

    private static func sanitized(_ feed: CampaignFeed) -> CampaignFeed? {
        let id = feed.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              CampaignFeed.normalizeYMD(feed.start) != nil,
              CampaignFeed.normalizeYMD(feed.end) != nil
        else { return nil }
        let prompts = feed.prompts
            .map { prompt -> CampaignPrompt in
                var copy = prompt
                copy.prompt = prompt.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.theme = prompt.theme?.trimmingCharacters(in: .whitespacesAndNewlines)
                copy.date = CampaignFeed.normalizeYMD(prompt.date) ?? prompt.date
                return copy
            }
            .filter { $0.day > 0 && !$0.prompt.isEmpty }
            .sorted { $0.day < $1.day }
        guard !prompts.isEmpty else { return nil }
        var zone = feed.timezone.trimmingCharacters(in: .whitespacesAndNewlines)
        if TimeZone(identifier: zone) == nil {
            zone = CampaignFeed.fallbackTimeZoneID
        }
        let title = feed.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return CampaignFeed(
            id: id,
            title: title.isEmpty ? CampaignFeed.cardTitle : title,
            start: CampaignFeed.normalizeYMD(feed.start) ?? feed.start,
            end: CampaignFeed.normalizeYMD(feed.end) ?? feed.end,
            timezone: zone,
            prompts: prompts
        )
    }

    // MARK: - Disk + network

    private struct DiskCache: Codable {
        var etag: String?
        var source: String?
        var savedAt: Date
        var feed: CampaignFeed
    }

    private enum FetchResult {
        case notModified
        case updated(CampaignFeed, etag: String?)
        case failed
    }

    private static func cacheFileURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Campaigns", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return directory.appendingPathComponent("november-2026.json")
    }

    private static func loadDisk() -> DiskCache? {
        guard let url = cacheFileURL(),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiskCache.self, from: data)
    }

    private static func saveDisk(_ feed: CampaignFeed, etag: String?, source: String?) {
        guard let url = cacheFileURL() else { return }
        let cache = DiskCache(etag: etag, source: source, savedAt: Date(), feed: feed)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func fetch(_ url: URL, etag: String?) async -> FetchResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 304 { return .notModified }
            guard (200...299).contains(http.statusCode) else { return .failed }
            let feed = try JSONDecoder().decode(CampaignFeed.self, from: data)
            let header = http.value(forHTTPHeaderField: "Etag") ?? http.value(forHTTPHeaderField: "ETag")
            return .updated(feed, etag: header)
        } catch {
            return .failed
        }
    }
}
