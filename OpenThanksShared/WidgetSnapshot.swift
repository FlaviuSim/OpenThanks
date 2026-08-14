import Foundation
import WidgetKit

/// Offline snapshot the main app writes; Home / Lock Screen widgets read it.
struct WidgetSnapshot: Codable, Equatable {
    var displayName: String?
    var sentThisMonth: Int
    var receivedTotal: Int
    var pendingToAccept: Int
    /// Most recent appreciation received (pending preferred, else latest accepted).
    var latestReceived: WidgetReceivedTeaser?
    var updatedAt: Date

    static let empty = WidgetSnapshot(
        displayName: nil,
        sentThisMonth: 0,
        receivedTotal: 0,
        pendingToAccept: 0,
        latestReceived: nil,
        updatedAt: .distantPast
    )

    var hasReceived: Bool { receivedTotal > 0 || pendingToAccept > 0 }

    /// Fresh appreciation waiting for you (pending accept) — not lifetime history or hearts.
    var hasAppreciationWaiting: Bool { pendingToAccept > 0 }
}

/// Compact teaser for the large Home Screen widget’s “recent received” panel.
struct WidgetReceivedTeaser: Codable, Equatable {
    var fromName: String
    var messagePreview: String
    var isPending: Bool

    static func preview(from message: String, maxChars: Int = 140) -> String {
        let trimmed = message
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.count <= maxChars { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxChars)
        var slice = String(trimmed[..<end])
        if let lastSpace = slice.lastIndex(of: " "),
           slice.distance(from: slice.startIndex, to: lastSpace) > 40 {
            slice = String(slice[..<lastSpace])
        }
        return slice.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
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
        case .someoneAppreciated: return "Open OpenThanks to accept it."
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
        // Only tease “someone appreciated you” when something is waiting to accept —
        // not for lifetime received history or hearts.
        if snapshot.hasAppreciationWaiting {
            pool.append(.someoneAppreciated)
        }
        // Bias medium toward monthlyCount without making it the only message.
        // Large uses a dedicated two-panel layout, so keep its prompt pool varied.
        #if os(iOS)
        if family == .systemMedium {
            pool.append(.monthlyCount)
            pool.append(.monthlyCount)
        }
        #endif
        let slot = hour / 4
        let index = (day + slot) % max(pool.count, 1)
        return pool[index]
    }
}

// MARK: - Large widget secondary panel

/// Lower half of the large / extra-large Home Screen widget.
enum WidgetLargeSecondary: Equatable {
    case received(WidgetReceivedTeaser)
    case reflection(headline: String, subtitle: String)

    var deepLink: URL {
        switch self {
        case .received:
            return WidgetDeepLink.received
        case .reflection:
            return WidgetDeepLink.compose
        }
    }

    static func resolve(at date: Date, snapshot: WidgetSnapshot) -> WidgetLargeSecondary {
        // Prefer a real appreciation when we have one — especially if it’s waiting.
        if let teaser = snapshot.latestReceived {
            if teaser.isPending { return .received(teaser) }
            // Rotate: most slots show the recent note; occasional slot shows a prompt.
            let hour = Calendar.current.component(.hour, from: date)
            if (hour / 4) % 3 != 2 {
                return .received(teaser)
            }
        }
        return reflection(at: date)
    }

    private static let reflections: [(String, String)] = [
        ("Who made your day easier?", "A short thank-you is enough."),
        ("Who deserves a thank you you’ve never said?", "Say it today."),
        ("Who quietly supports you?", "They’ll remember this note."),
        ("Who made you smile this week?", "Capture it before it fades."),
        ("Who believed in you first?", "They’d love to hear it."),
        ("Who helped without being asked?", "Open a blank appreciation."),
    ]

    private static func reflection(at date: Date) -> WidgetLargeSecondary {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let hour = Calendar.current.component(.hour, from: date)
        let index = (day + hour / 4) % reflections.count
        let pair = reflections[index]
        return .reflection(headline: pair.0, subtitle: pair.1)
    }
}
