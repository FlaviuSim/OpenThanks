import Foundation
import WidgetKit

/// Offline snapshot the main app writes; Home / Lock Screen widgets read it.
struct WidgetSnapshot: Codable, Equatable {
    var displayName: String?
    var sentThisMonth: Int
    var receivedTotal: Int
    var pendingToAccept: Int
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        displayName: nil,
        sentThisMonth: 0,
        receivedTotal: 0,
        pendingToAccept: 0,
        updatedAt: .distantPast
    )

    var hasReceived: Bool { receivedTotal > 0 || pendingToAccept > 0 }
}

enum WidgetSnapshotStore {
    private static let key = "widgetSnapshot.v1"

    static func load() -> WidgetSnapshot {
        guard let data = AppGroup.defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        AppGroup.defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        AppGroup.defaults.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Prompt copy (handwritten note energy, not a game streak)

enum WidgetPromptKind: String, CaseIterable, Codable {
    case whoHelped
    case thankSomeone
    case monthlyCount
    case someoneAppreciated
    case sendThanks
    case viewReceived

    var headline: String {
        switch self {
        case .whoHelped: return "Who helped you this week?"
        case .thankSomeone: return "Thank someone today."
        case .monthlyCount: return "You’ve thanked people this month."
        case .someoneAppreciated: return "Someone appreciated you."
        case .sendThanks: return "Send thanks"
        case .viewReceived: return "View received thanks"
        }
    }

    func headline(for snapshot: WidgetSnapshot) -> String {
        switch self {
        case .monthlyCount:
            let n = snapshot.sentThisMonth
            if n <= 0 { return "Thank someone this month." }
            if n == 1 { return "You’ve thanked 1 person this month." }
            return "You’ve thanked \(n) people this month."
        case .someoneAppreciated:
            if snapshot.pendingToAccept > 0 {
                let n = snapshot.pendingToAccept
                return n == 1
                    ? "Someone appreciated you."
                    : "\(n) appreciations are waiting."
            }
            if snapshot.receivedTotal > 0 {
                return "Someone appreciated you."
            }
            return "Thank someone today."
        default:
            return headline
        }
    }

    var subtitle: String {
        switch self {
        case .whoHelped: return "A short note goes a long way."
        case .thankSomeone: return "Open a blank appreciation."
        case .monthlyCount: return "Keep the habit gentle."
        case .someoneAppreciated: return "Take a moment to read it."
        case .sendThanks: return "One tap to write."
        case .viewReceived: return "See what’s waiting."
        }
    }

    var deepLink: URL {
        switch self {
        case .viewReceived, .someoneAppreciated:
            return WidgetDeepLink.received
        default:
            return WidgetDeepLink.compose
        }
    }

    /// Rotate prompts through the day so the Home Screen feels alive, not static.
    /// Medium favors the monthly count more often so the larger size stays stats-forward.
    static func prompt(
        at date: Date,
        snapshot: WidgetSnapshot,
        family: WidgetFamily? = nil
    ) -> WidgetPromptKind {
        let hour = Calendar.current.component(.hour, from: date)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        var pool: [WidgetPromptKind] = [.whoHelped, .thankSomeone, .monthlyCount]
        if snapshot.hasReceived {
            pool.append(.someoneAppreciated)
        }
        // Bias medium / large toward monthlyCount without making it the only message.
        #if os(iOS)
        if family == .systemMedium || family == .systemLarge || family == .systemExtraLarge {
            pool.append(.monthlyCount)
            pool.append(.monthlyCount)
        }
        #endif
        let slot = hour / 4
        let index = (day + slot) % max(pool.count, 1)
        return pool[index]
    }
}
