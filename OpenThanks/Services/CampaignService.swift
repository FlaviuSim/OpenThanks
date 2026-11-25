import Foundation
import Observation

/// One day from the remote campaign feed.
struct CampaignPrompt: Codable, Equatable, Sendable, Identifiable {
    var day: Int
    var date: String
    var theme: String?
    var prompt: String
    var example: String?
    /// Remote button label (`cta`). Nil when the feed omitted it.
    var cta: String?

    var id: Int { day }
}

/// `{ id, title, start, end, timezone, cta, prompts: [{ day, date, theme, prompt, example, cta }] }`
/// from `https://openthanks.com/campaigns/{id}.json`.
struct CampaignFeed: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var start: String
    var end: String
    var timezone: String
    var prompts: [CampaignPrompt]
    /// Remote button label for every day that does not set its own `cta`.
    var cta: String?

    static let november2026ID = "november-2026"
    static let sixFor2026ID = "six-for-2026"
    static let cardTitle = "30 Days of Thanks"
    static let sixFor2026CardTitle = "Six for '26"
    static let fallbackTimeZoneID = "America/New_York"

    /// Active campaign for the Eastern calendar day (Nov → november; Dec+ → six-for-2026).
    static func activeCampaignID(at date: Date = Date()) -> String {
        let zone = TimeZone(identifier: fallbackTimeZoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let ymd = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        if ymd >= "2026-12-01" { return sixFor2026ID }
        return november2026ID
    }

    static func jsonURL(for id: String) -> URL {
        URL(string: "https://openthanks.com/campaigns/\(id).json")!
    }

    static func apiURL(for id: String) -> URL {
        URL(string: "https://openthanks.com/api/campaigns/\(id)")!
    }

    static var jsonURL: URL { jsonURL(for: activeCampaignID()) }
    static var apiURL: URL { apiURL(for: activeCampaignID()) }

    var isSixFor2026: Bool { id == Self.sixFor2026ID }

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
    /// Six for '26 progress is slot-based (6), not Dec day count (31).
    var inclusiveDayCount: Int {
        if isSixFor2026 { return max(prompts.count, 1) }
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

    init(
        id: String,
        title: String,
        start: String,
        end: String,
        timezone: String,
        prompts: [CampaignPrompt],
        cta: String? = nil
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.timezone = timezone
        self.prompts = prompts
        self.cta = cta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        start = try container.decode(String.self, forKey: .start)
        end = try container.decode(String.self, forKey: .end)
        let zone = try container.decodeIfPresent(String.self, forKey: .timezone)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        timezone = (zone?.isEmpty == false) ? zone! : Self.fallbackTimeZoneID
        prompts = try container.decode([CampaignPrompt].self, forKey: .prompts)
        cta = CampaignPromptCardModel.normalizeLabel(
            try container.decodeIfPresent(String.self, forKey: .cta)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(start, forKey: .start)
        try container.encode(end, forKey: .end)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(prompts, forKey: .prompts)
        try container.encodeIfPresent(cta, forKey: .cta)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, start, end, timezone, prompts, cta
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
    /// Progress count for the Home card. November: distinct send days. Six for '26: public-accepted qualifying slots.
    private(set) var daysSent: Int?
    /// Six for '26: favorite nonprofit on profile (needed to claim).
    private(set) var hasFavoriteNonprofit: Bool = false
    /// Six for '26: server rank after claim, if any.
    private(set) var finisherRank: Int?
    private(set) var finisherStatus: String?
    /// Six for '26: public-accepted thank-yous that already count (order = slot 1…n).
    private(set) var sixFor2026Counted: [GratitudeService.SixFor2026SlotEntry] = []
    /// Six for '26: pending public sends that would count once accepted.
    private(set) var sixFor2026Pending: [GratitudeService.SixFor2026SlotEntry] = []
    #if DEBUG
    /// yyyy-MM-dd stand-in for "today". Release builds ignore this.
    private(set) var debugDateYMD: String?
    #endif

    private var sentDayKeys: Set<String> = []
    private var progressLoaded = false
    private var lastRevalidatedAt: Date?
    private var refreshTask: Task<Void, Never>?
    private var activeFeedID: String = CampaignFeed.activeCampaignID()

    private init() {
        #if DEBUG
        if let stored = UserDefaults.standard.string(forKey: Self.debugDateKey) {
            debugDateYMD = CampaignFeed.normalizeYMD(stored)
        }
        #endif
        activeFeedID = desiredFeedID()
        if let disk = Self.loadDisk(id: activeFeedID) {
            apply(disk.feed, persist: false)
            lastRevalidatedAt = disk.savedAt
        }
    }

    var todayPrompt: CampaignPrompt? {
        promptForUI()
    }

    var progressTotal: Int {
        feed?.inclusiveDayCount ?? (feed?.isSixFor2026 == true ? 6 : 30)
    }

    var canClaimSixFor2026: Bool {
        guard feed?.isSixFor2026 == true else { return false }
        return (daysSent ?? 0) >= progressTotal && hasFavoriteNonprofit && finisherRank == nil
    }

    /// Prompt for the UI clock: the debug override in DEBUG, otherwise now.
    func promptForUI(at date: Date = Date()) -> CampaignPrompt? {
        guard let feed else { return nil }
        #if DEBUG
        if let debugDateYMD {
            if feed.isSixFor2026 {
                return sixFor2026Prompt(onYMD: debugDateYMD, feed: feed)
            }
            return feed.prompt(onYMD: debugDateYMD)
        }
        #endif
        if feed.isSixFor2026 {
            return sixFor2026Prompt(onYMD: feed.ymd(for: date), feed: feed)
        }
        return feed.prompt(on: date)
    }

    /// Inside December: show next incomplete slot (1…6), not a calendar-day match.
    private func sixFor2026Prompt(onYMD ymd: String, feed: CampaignFeed) -> CampaignPrompt? {
        guard feed.contains(ymd: ymd) else { return nil }
        let qualified = daysSent ?? 0
        if qualified >= feed.prompts.count {
            return feed.prompts.last
        }
        return feed.prompt(day: qualified + 1) ?? feed.prompts.first
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

    /// November: distinct send days. Six for '26: public-accepted qualifying RPC count.
    func refreshProgress(authorId: UUID) async {
        guard let feed, let start = feed.windowStart, let end = feed.windowEnd else {
            daysSent = nil
            sentDayKeys = []
            sixFor2026Counted = []
            sixFor2026Pending = []
            progressLoaded = false
            return
        }
        // Six for '26: show the card all December even before a "today" calendar prompt.
        if !feed.isSixFor2026, todayPrompt == nil {
            daysSent = nil
            sentDayKeys = []
            sixFor2026Counted = []
            sixFor2026Pending = []
            progressLoaded = false
            return
        }
        if feed.isSixFor2026 {
            do {
                let progress = try await GratitudeService.sixFor2026Progress(authorId: authorId)
                daysSent = progress.qualified
                hasFavoriteNonprofit = progress.hasNonprofit
                finisherRank = progress.finisherRank
                finisherStatus = progress.finisherStatus
                sixFor2026Counted = progress.counted
                sixFor2026Pending = progress.pending
                progressLoaded = true
            } catch {
                // Keep the last count when offline.
            }
            return
        }
        sixFor2026Counted = []
        sixFor2026Pending = []
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
    /// Six for '26 waits for public accept — do not bump optimistically.
    func noteSent(at date: Date) {
        guard progressLoaded, let feed, !feed.isSixFor2026 else { return }
        let key = feed.ymd(for: date)
        guard feed.contains(ymd: key) else { return }
        guard sentDayKeys.insert(key).inserted else { return }
        daysSent = sentDayKeys.count
    }

    @discardableResult
    func claimSixFor2026Finisher() async -> String {
        do {
            let result = try await GratitudeService.claimSixFor2026Finisher()
            if let rank = result.rank { finisherRank = rank }
            finisherStatus = result.status
            var props: [String: Any] = ["campaign": CampaignFeed.sixFor2026ID]
            if let rank = result.rank { props["rank"] = rank }
            if let status = result.status { props["status"] = status }
            Analytics.capture(
                result.poolFull ? "six26_pool_full" : (result.ok ? "six26_rank_assigned" : "six26_complete_submitted"),
                props
            )
            return result.message ?? (result.ok ? "Claimed." : "Could not claim yet.")
        } catch {
            return error.localizedDescription
        }
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

    /// Deep link / universal link (e.g. App Store event → `/six-for-26`).
    /// Resolves the **linked** campaign feed even when Home still shows November,
    /// so pre-December event taps get Six for '26 chrome instead of a blank form.
    func openCompose(link: CampaignComposeLink, analyticsSource: String) async {
        let match = await resolvePromptForDeepLink(link)
        let hint = match?.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        ComposeLaunchBridge.shared.queue(
            campaignHint: (hint?.isEmpty == false) ? hint : nil,
            campaignId: link.id,
            campaignDay: match?.day ?? link.day,
            analyticsSource: analyticsSource
        )
        Task {
            await CampaignPushOffer.offer(moment: .joined)
        }
    }

    /// Memory → disk → network for `link.id`, without replacing an active November Home feed.
    private func resolvePromptForDeepLink(_ link: CampaignComposeLink) async -> CampaignPrompt? {
        if let match = resolvedPrompt(for: link) {
            return match
        }
        if let disk = Self.loadDisk(id: link.id),
           let clean = Self.sanitized(disk.feed),
           let match = prompt(from: clean, link: link) {
            return match
        }
        if let remote = await fetchFeedOnce(id: link.id) {
            if link.id == desiredFeedID() {
                apply(remote, persist: false)
            }
            return prompt(from: remote, link: link)
        }
        if feed == nil {
            await refresh()
            return resolvedPrompt(for: link)
        }
        return nil
    }

    private func prompt(from feed: CampaignFeed, link: CampaignComposeLink) -> CampaignPrompt? {
        guard feed.id == link.id else { return nil }
        if let day = link.day {
            return feed.prompt(day: day)
        }
        if feed.isSixFor2026 {
            // Event landing with no day → first slot (works before Dec 1 too).
            return feed.prompt(day: 1) ?? feed.prompts.first
        }
        return feed.prompt(on: uiClockDate()) ?? feed.prompts.first
    }

    /// One-shot fetch for a campaign id; caches to disk. Does not mutate `self.feed`.
    private func fetchFeedOnce(id: String) async -> CampaignFeed? {
        let cached = Self.loadDisk(id: id)
        let urls = [CampaignFeed.jsonURL(for: id), CampaignFeed.apiURL(for: id)]
        for url in urls {
            let etag = (cached?.source == url.absoluteString) ? cached?.etag : nil
            switch await Self.fetch(url, etag: etag) {
            case .notModified:
                return cached.flatMap { Self.sanitized($0.feed) }
            case .updated(let decoded, let etag):
                guard let clean = Self.sanitized(decoded) else { continue }
                Self.saveDisk(clean, etag: etag, source: url.absoluteString)
                return clean
            case .failed:
                continue
            }
        }
        return cached.flatMap { Self.sanitized($0.feed) }
    }

    #if DEBUG
    func setDebugDate(_ date: Date) {
        let zone = TimeZone(identifier: CampaignFeed.fallbackTimeZoneID) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let ymd = String(format: "%04d-%02d-%02d", year, month, day)
        debugDateYMD = CampaignFeed.normalizeYMD(ymd)
        if let debugDateYMD {
            UserDefaults.standard.set(debugDateYMD, forKey: Self.debugDateKey)
        }
        Task { await refresh() }
    }

    func clearDebugDate() {
        debugDateYMD = nil
        UserDefaults.standard.removeObject(forKey: Self.debugDateKey)
        Task { await refresh() }
    }

    /// Default preview jump: first day of Six for '26 (December).
    static func debugPreviewStart() -> Date {
        CampaignFeed.date(
            ymd: "2026-12-01",
            timeZone: TimeZone(identifier: CampaignFeed.fallbackTimeZoneID) ?? .current,
            hour: 12
        ) ?? Date()
    }

    static func debugPreviewNovemberStart() -> Date {
        CampaignFeed.date(
            ymd: "2026-11-01",
            timeZone: TimeZone(identifier: CampaignFeed.fallbackTimeZoneID) ?? .current,
            hour: 12
        ) ?? Date()
    }
    #endif

    /// Feed id for the UI clock (DEBUG preview date when set).
    private func desiredFeedID(at date: Date = Date()) -> String {
        CampaignFeed.activeCampaignID(at: uiClockDate(at: date))
    }

    private func uiClockDate(at date: Date = Date()) -> Date {
        #if DEBUG
        if let debugDateYMD,
           let override = CampaignFeed.date(
               ymd: debugDateYMD,
               timeZone: TimeZone(identifier: CampaignFeed.fallbackTimeZoneID) ?? .current,
               hour: 12
           ) {
            return override
        }
        #endif
        return date
    }

    // MARK: - Refresh

    private func performRefresh() async {
        let desiredID = desiredFeedID()
        if desiredID != activeFeedID {
            activeFeedID = desiredID
            lastRevalidatedAt = nil
            progressLoaded = false
            daysSent = nil
            sentDayKeys = []
            if let disk = Self.loadDisk(id: desiredID) {
                apply(disk.feed, persist: false)
            } else {
                feed = nil
                CampaignFeedCache.shared.update(nil)
            }
        }

        let current = feed
        guard shouldRevalidate(current) else { return }

        let cached = Self.loadDisk(id: desiredID)
        let urls = [CampaignFeed.jsonURL(for: desiredID), CampaignFeed.apiURL(for: desiredID)]
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
        if desiredFeedID() != activeFeedID { return true }
        guard let lastRevalidatedAt else { return true }
        if Date().timeIntervalSince(lastRevalidatedAt) > Self.freshInterval { return true }
        let clock = uiClockDate()
        if let feed, feed.ymd(for: lastRevalidatedAt) != feed.ymd(for: clock) { return true }
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
                copy.cta = CampaignPromptCardModel.normalizeLabel(prompt.cta)
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
            title: title,
            start: CampaignFeed.normalizeYMD(feed.start) ?? feed.start,
            end: CampaignFeed.normalizeYMD(feed.end) ?? feed.end,
            timezone: zone,
            prompts: prompts,
            cta: CampaignPromptCardModel.normalizeLabel(feed.cta)
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

    private static func cacheFileURL(id: String = CampaignFeed.activeCampaignID()) -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = base.appendingPathComponent("Campaigns", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return directory.appendingPathComponent("\(id).json")
    }

    private static func loadDisk(id: String = CampaignFeed.activeCampaignID()) -> DiskCache? {
        guard let url = cacheFileURL(id: id),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DiskCache.self, from: data)
    }

    private static func saveDisk(_ feed: CampaignFeed, etag: String?, source: String?) {
        guard let url = cacheFileURL(id: feed.id) else { return }
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
