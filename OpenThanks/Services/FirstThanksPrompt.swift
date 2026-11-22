import Foundation

/// A visit is one stretch of using the app. A new visit starts on the first
/// open, after about 30 minutes away, or on a new calendar day — whichever
/// comes first. Killing and reopening inside that window stays the same visit.
struct AppVisitState: Equatable, Sendable {
    var number: Int
    var lastActivityAt: Date?
}

enum AppVisit {
    static let inactivityGap: TimeInterval = 30 * 60
    static let numberKey = "appVisit.number.v1"
    static let lastActivityKey = "appVisit.lastActivity.v1"

    /// First open is visit 1. Later opens stay on that visit until the gap or a new day.
    static func advance(
        state: AppVisitState,
        now: Date,
        calendar: Calendar = .current
    ) -> AppVisitState {
        guard state.number > 0, let last = state.lastActivityAt else {
            return AppVisitState(number: 1, lastActivityAt: now)
        }
        let newDay = !calendar.isDate(last, inSameDayAs: now)
        let idle = now.timeIntervalSince(last) >= inactivityGap
        if newDay || idle {
            return AppVisitState(number: state.number + 1, lastActivityAt: now)
        }
        return AppVisitState(number: state.number, lastActivityAt: now)
    }

    static func load(from defaults: UserDefaults) -> AppVisitState {
        let number = defaults.integer(forKey: numberKey)
        let last = defaults.object(forKey: lastActivityKey) as? TimeInterval
        return AppVisitState(
            number: number,
            lastActivityAt: last.map(Date.init(timeIntervalSince1970:))
        )
    }

    static func save(_ state: AppVisitState, to defaults: UserDefaults) {
        defaults.set(state.number, forKey: numberKey)
        if let last = state.lastActivityAt {
            defaults.set(last.timeIntervalSince1970, forKey: lastActivityKey)
        }
    }

    /// Foreground or cold start. May start a new visit, then stamps activity.
    @discardableResult
    static func recordReturn(
        in defaults: UserDefaults,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let next = advance(state: load(from: defaults), now: now, calendar: calendar)
        save(next, to: defaults)
        return next.number
    }

    /// Leaving the app. Moves the idle clock to now so a long session is not
    /// treated as time away.
    static func noteActivity(in defaults: UserDefaults, now: Date = Date()) {
        var state = load(from: defaults)
        guard state.number > 0 else { return }
        state.lastActivityAt = now
        save(state, to: defaults)
    }
}

/// Home has no screen-view event today. This decides when `home_viewed` fires,
/// including the first time Home is shown. A re-tap passes `force` so it still
/// counts after the duplicate window.
enum HomeScreenView {
    static let event = "home_viewed"
    /// Appear and the matching foreground at launch are one view.
    static let duplicateWindow: TimeInterval = 1

    static func shouldCapture(lastCapturedAt: Date?, now: Date, force: Bool = false) -> Bool {
        if force { return true }
        guard let lastCapturedAt else { return true }
        return now.timeIntervalSince(lastCapturedAt) >= duplicateWindow
    }
}

enum FirstThanksPersonSource: String, Equatable, Sendable {
    case thankedYou = "thanked_you"
    case calendar
    case recent

    var rank: Int {
        switch self {
        case .thankedYou: 0
        case .calendar: 1
        case .recent: 2
        }
    }

    var subtitle: String {
        switch self {
        case .thankedYou: "Thanked you"
        case .calendar: "From your week"
        case .recent: "Recently here"
        }
    }
}

enum FirstThanksRelationship: String, CaseIterable, Equatable, Sendable {
    case teacher
    case coach
    case mentor
    case friend
    case mom

    var title: String {
        switch self {
        case .teacher: "Teacher"
        case .coach: "Coach"
        case .mentor: "Mentor"
        case .friend: "Friend"
        case .mom: "Mom"
        }
    }
}

enum FirstThanksSuggestionKind: String, Equatable, Sendable {
    case people
    case relationships
}

struct FirstThanksCandidate: Equatable, Sendable {
    var id: String
    var name: String
    var source: FirstThanksPersonSource
}

enum FirstThanksSuggestion: Equatable, Identifiable, Sendable {
    case person(id: String, name: String, source: FirstThanksPersonSource)
    case relationship(FirstThanksRelationship)

    var id: String {
        switch self {
        case .person(let id, _, _): "person-\(id)"
        case .relationship(let relationship): "relationship-\(relationship.rawValue)"
        }
    }
}

struct FirstThanksSuggestionSet: Equatable, Sendable {
    var items: [FirstThanksSuggestion]
    var kind: FirstThanksSuggestionKind
}

/// People to offer on the Home card. Existing sources win; relationship chips
/// are the fallback when nobody is on hand.
enum FirstThanksSuggestions {
    static let maxPeople = 3

    static func resolve(_ candidates: [FirstThanksCandidate]) -> FirstThanksSuggestionSet {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.source.rank != rhs.source.rank { return lhs.source.rank < rhs.source.rank }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        var seen = Set<String>()
        var people: [FirstThanksSuggestion] = []
        for candidate in ranked {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            people.append(.person(id: candidate.id, name: name, source: candidate.source))
            if people.count == maxPeople { break }
        }
        if !people.isEmpty {
            return FirstThanksSuggestionSet(items: people, kind: .people)
        }
        return FirstThanksSuggestionSet(
            items: FirstThanksRelationship.allCases.map { .relationship($0) },
            kind: .relationships
        )
    }
}

/// Signed-in, never sent, visit 2 or later, and not dismissed on this visit.
enum FirstThanksCardRule {
    static let minimumVisit = 2
    static let dismissedVisitKey = "firstThanksCard.dismissedVisit.v1"
    static let shownVisitKey = "firstThanksCard.shownVisit.v1"

    static func shouldShow(
        isSignedIn: Bool,
        hasSentThankYou: Bool,
        visitNumber: Int,
        dismissedOnVisit: Int?
    ) -> Bool {
        guard isSignedIn, !hasSentThankYou else { return false }
        guard visitNumber >= minimumVisit else { return false }
        if let dismissedOnVisit, dismissedOnVisit == visitNumber { return false }
        return true
    }

    static func shouldCaptureShown(visitNumber: Int, lastCapturedVisit: Int?) -> Bool {
        guard visitNumber > 0 else { return false }
        return lastCapturedVisit != visitNumber
    }

    static func dismissedVisit(in defaults: UserDefaults) -> Int? {
        guard defaults.object(forKey: dismissedVisitKey) != nil else { return nil }
        let value = defaults.integer(forKey: dismissedVisitKey)
        return value > 0 ? value : nil
    }

    static func dismiss(visitNumber: Int, in defaults: UserDefaults) {
        defaults.set(visitNumber, forKey: dismissedVisitKey)
    }

    /// One `first_thanks_card_shown` per visit, even if Home appears twice.
    @discardableResult
    static func markShownIfNeeded(visitNumber: Int, in defaults: UserDefaults) -> Bool {
        let last: Int? = defaults.object(forKey: shownVisitKey) == nil
            ? nil
            : defaults.integer(forKey: shownVisitKey)
        guard shouldCaptureShown(visitNumber: visitNumber, lastCapturedVisit: last) else {
            return false
        }
        defaults.set(visitNumber, forKey: shownVisitKey)
        return true
    }
}
