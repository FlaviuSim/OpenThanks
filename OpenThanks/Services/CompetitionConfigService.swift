import Foundation

/// Fetches and caches the remote `competition` row from `app_config`.
enum CompetitionConfigService {
    private static let cacheKey = "competitionConfig.v1"
    private static let cacheAtKey = "competitionConfig.cachedAt.v1"
    private static let ttl: TimeInterval = 15 * 60

    private static let lock = NSLock()
    private static var _cached: CompetitionConfig = loadCache() ?? .disabled

    static var cached: CompetitionConfig {
        lock.lock()
        defer { lock.unlock() }
        return _cached
    }

    static func refresh(force: Bool = false) async -> CompetitionConfig {
        if !force,
           let cachedAt = UserDefaults.standard.object(forKey: cacheAtKey) as? Date,
           Date().timeIntervalSince(cachedAt) < ttl,
           let existing = loadCache() {
            setCached(existing)
            return existing
        }

        do {
            struct Row: Decodable {
                let value: CompetitionConfig
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                try Self.decodeISO8601(decoder)
            }

            // Fetch raw JSON so we control date decoding for nested jsonb.
            let response = try await supabase.from("app_config")
                .select("value")
                .eq("key", value: "competition")
                .single()
                .execute()
            let row = try decoder.decode(Row.self, from: response.data)
            setCached(row.value)
            saveCache(row.value)
            return row.value
        } catch {
            // Fail closed: hide competition UI if remote config is missing.
            if let existing = loadCache() {
                setCached(existing)
                return existing
            }
            setCached(.disabled)
            return .disabled
        }
    }

    // MARK: - Cache

    private static func setCached(_ config: CompetitionConfig) {
        lock.lock()
        _cached = config
        lock.unlock()
    }

    private static func loadCache() -> CompetitionConfig? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            try Self.decodeISO8601(decoder)
        }
        return try? decoder.decode(CompetitionConfig.self, from: data)
    }

    private static func saveCache(_ config: CompetitionConfig) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(config) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date(), forKey: cacheAtKey)
    }

    private static func decodeISO8601(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid date: \(raw)"
        )
    }
}
