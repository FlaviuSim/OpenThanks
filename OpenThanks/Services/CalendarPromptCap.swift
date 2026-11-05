import Foundation

/// Where an automatic calendar connect sheet is coming from.
enum CalendarPromptSource: Equatable, Sendable {
    /// Full-screen gate on the 3rd main-app open. Repeated every launch before the cap.
    case deferredOpen
    /// Sheet after a send, when notifications are already decided.
    case postSend
    /// Sheet after an accept. Never shown.
    case postAccept
    /// The person asked: Home banner or Settings. Not capped.
    case userInitiated
}

struct CalendarPromptCapState: Equatable, Sendable {
    var shownCount: Int?
    var lastRecordedAt: Date?
}

/// Automatic calendar prompts, at most twice per person.
///
/// The count lives in `UserDefaults` (`shownCountKey`). Before that key exists,
/// launches from the 3rd open onward already showed the deferred gate, so those
/// opens count as shows already spent.
enum CalendarPromptCap {
    static let maximumAutomaticShows = 2
    static let shownCountKey = "calendarPrompt.automaticShownCount.v1"
    static let lastRecordedAtKey = "calendarPrompt.automaticShownAt.v1"
    /// SwiftUI can call `onAppear` twice for one presentation.
    static let duplicateAppearWindow: TimeInterval = 2

    static func shouldShowAutomatic(
        source: CalendarPromptSource,
        shownCount: Int,
        acceptedThisSession: Bool,
        calendarConnected: Bool,
        now: Date = Date(),
        cooldownUntil: Date? = nil
    ) -> Bool {
        switch source {
        case .userInitiated:
            return true
        case .postAccept:
            return false
        case .deferredOpen, .postSend:
            if calendarConnected || acceptedThisSession { return false }
            if shownCount >= maximumAutomaticShows { return false }
            if let cooldownUntil, now < cooldownUntil { return false }
            return true
        }
    }

    /// Shows already consumed before `shownCountKey` existed.
    /// Open 3 is the first eligible presentation, so it is not a past show.
    static func inferredShownCount(mainAppOpenCount: Int) -> Int {
        min(maximumAutomaticShows, max(0, mainAppOpenCount - 3))
    }

    static func effectiveShownCount(stored: Int?, mainAppOpenCount: Int) -> Int {
        if let stored { return max(0, stored) }
        return inferredShownCount(mainAppOpenCount: mainAppOpenCount)
    }

    static func recordShow(
        state: CalendarPromptCapState,
        mainAppOpenCount: Int,
        now: Date
    ) -> CalendarPromptCapState {
        if let last = state.lastRecordedAt, now.timeIntervalSince(last) < duplicateAppearWindow {
            return state
        }
        let current = effectiveShownCount(stored: state.shownCount, mainAppOpenCount: mainAppOpenCount)
        return CalendarPromptCapState(shownCount: current + 1, lastRecordedAt: now)
    }

    static func storedShownCount(from defaults: UserDefaults) -> Int? {
        guard defaults.object(forKey: shownCountKey) != nil else { return nil }
        return defaults.integer(forKey: shownCountKey)
    }

    static func load(from defaults: UserDefaults, mainAppOpenCount: Int) -> Int {
        effectiveShownCount(
            stored: storedShownCount(from: defaults),
            mainAppOpenCount: mainAppOpenCount
        )
    }

    static func record(
        in defaults: UserDefaults,
        mainAppOpenCount: Int,
        now: Date = Date()
    ) {
        let state = CalendarPromptCapState(
            shownCount: storedShownCount(from: defaults),
            lastRecordedAt: defaults.object(forKey: lastRecordedAtKey) as? Date
        )
        let next = recordShow(state: state, mainAppOpenCount: mainAppOpenCount, now: now)
        guard next != state else { return }
        if let count = next.shownCount {
            defaults.set(count, forKey: shownCountKey)
        }
        if let recordedAt = next.lastRecordedAt {
            defaults.set(recordedAt, forKey: lastRecordedAtKey)
        }
    }
}
