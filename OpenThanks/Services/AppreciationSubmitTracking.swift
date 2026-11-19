import Foundation

/// Whether a successful save inserted a new thank-you or changed one that
/// already exists.
///
/// Pending review, a Watch note opened again on the phone, and any later
/// re-save are updates. A queued first insert (offline Watch draft, or a
/// Watch note the phone saves because no row existed yet) is a create.
enum AppreciationSaveKind: Equatable, Sendable {
    case created
    case updated
}

/// PostHog action for that save.
///
/// `submit` is `appreciation_submitted`, the send counter. It is allowed once
/// per gratitude id. `edit` is `appreciation_edited`. `ignoreDuplicateSubmit`
/// is a replay of a create this device already counted (queue flush, retry
/// that returns the same row, second tap).
enum AppreciationSaveAnalytics: Equatable, Sendable {
    case submit
    case edit
    case ignoreDuplicateSubmit
}

/// Decides which appreciations have already counted as a send, and remembers
/// them on this device.
enum AppreciationSubmitTracking {
    static let storageKey = "openthanks.appreciationSubmittedIds.v1"

    private static let lock = NSLock()
    private static var stored = AppreciationSubmitLedger(defaults: .standard)

    /// Pure rule. `previouslySubmitted` is the set of gratitude ids that
    /// already fired `appreciation_submitted` on this device.
    ///
    /// An update never submits, including when the id is absent from the
    /// ledger (the row was created on an older build, or on another device).
    /// A create submits only the first time that id is seen.
    static func action(
        kind: AppreciationSaveKind,
        gratitudeId: UUID,
        previouslySubmitted: Set<UUID>
    ) -> AppreciationSaveAnalytics {
        switch kind {
        case .updated:
            return .edit
        case .created:
            if previouslySubmitted.contains(gratitudeId) {
                return .ignoreDuplicateSubmit
            }
            return .submit
        }
    }

    /// Records a new row as a send. Returns false when this id was already
    /// counted, so a replay cannot increment the counter.
    /// Updates must not call this — an edit of an id that was never recorded
    /// here would otherwise look like a first send.
    @discardableResult
    static func claimCreated(_ gratitudeId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored.claimCreated(gratitudeId)
    }
}

/// Device ledger of gratitude ids whose insert already counted.
/// Create one per store so tests do not share the process-wide ledger.
struct AppreciationSubmitLedger {
    var defaults: UserDefaults
    var storageKey: String
    private var cached: Set<UUID>?

    init(
        defaults: UserDefaults,
        storageKey: String = AppreciationSubmitTracking.storageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    @discardableResult
    mutating func claimCreated(_ gratitudeId: UUID) -> Bool {
        var known = load()
        let decision = AppreciationSubmitTracking.action(
            kind: .created,
            gratitudeId: gratitudeId,
            previouslySubmitted: known
        )
        guard decision == .submit else { return false }
        known.insert(gratitudeId)
        cached = known
        defaults.set(known.map { $0.uuidString.lowercased() }, forKey: storageKey)
        return true
    }

    private mutating func load() -> Set<UUID> {
        if let cached { return cached }
        let raw = defaults.stringArray(forKey: storageKey) ?? []
        let parsed = Set(raw.compactMap(UUID.init(uuidString:)))
        cached = parsed
        return parsed
    }
}
