import Foundation

/// Sticky A/B copy for opening the compose form (blank / campaign / notification).
/// Assignment is local — PostHog only receives `prompt_experiment` + `prompt_variant`.
enum ComposeOpenCopy {
    static let experimentKey = "compose_open_copy_v1"
    static let variantStorageKey = "composeOpenCopy.variant.v1"
    static let installIdKey = "composeOpenCopy.installId.v1"

    /// Formerly shown under the message field; compose no longer displays it.
    static let reassurance: String? = nil

    enum Family: String, CaseIterable, Equatable {
        case blank
        case campaign
        case notification
    }

    enum Variant: String, CaseIterable, Equatable {
        case control
        case directed
        case softStart = "soft_start"
    }

    struct Pack: Equatable {
        let experiment: String
        let family: Family
        let variant: Variant
        /// Banner title for two-step write (nil = hide custom banner chrome).
        let bannerTitle: String?
        let bannerBody: String?
        let reassurance: String?
        let placeholder: String
        /// Prefill only when the message field is still empty.
        let softStarter: String?
    }

    // MARK: - Assignment

    /// Sticky variant for this install / user. Never flips after first assignment.
    static func assignedVariant(
        distinctId: String?,
        defaults: UserDefaults = .standard
    ) -> Variant {
        if let raw = defaults.string(forKey: variantStorageKey),
           let stored = Variant(rawValue: raw) {
            return stored
        }
        let seed = stableDistinctId(distinctId, defaults: defaults)
        let bucket = Int(stableHash("\(experimentKey):\(seed)") % 3)
        let variant = Variant.allCases[bucket]
        defaults.set(variant.rawValue, forKey: variantStorageKey)
        return variant
    }

    /// Pure bucketing helper for tests (does not persist).
    static func variantForSeed(_ seed: String) -> Variant {
        let bucket = Int(stableHash("\(experimentKey):\(seed)") % 3)
        return Variant.allCases[bucket]
    }

    // MARK: - Family

    /// Editing skips the experiment. Campaign fields win over source prefixes.
    static func family(
        source: String,
        hasCampaign: Bool,
        isEditing: Bool
    ) -> Family? {
        if isEditing { return nil }
        if hasCampaign || source.hasPrefix("campaign") { return .campaign }
        switch source {
        case "notification_friday",
             "calendar_evening_nudge",
             "post_accept_remind",
             "notification_thank_reminder",
             "draft_reminder",
             "streak_live_activity_wake":
            return .notification
        default:
            return .blank
        }
    }

    // MARK: - Packs

    static func pack(
        family: Family,
        variant: Variant,
        campaignHint: String? = nil,
        customPlaceholder: String? = nil
    ) -> Pack {
        let trimmedCustom = customPlaceholder?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackPlaceholder: String = {
            if let trimmedCustom, !trimmedCustom.isEmpty { return trimmedCustom }
            return "Thank you for..."
        }()

        switch family {
        case .campaign:
            return campaignPack(variant: variant, placeholder: fallbackPlaceholder)
        case .blank, .notification:
            return blankOrNotificationPack(
                family: family,
                variant: variant,
                placeholder: fallbackPlaceholder
            )
        }
    }

    private static func blankOrNotificationPack(
        family: Family,
        variant: Variant,
        placeholder: String
    ) -> Pack {
        switch variant {
        case .control:
            return Pack(
                experiment: experimentKey,
                family: family,
                variant: variant,
                bannerTitle: "Write your appreciation",
                bannerBody: "Add your message and an optional photo. Next you’ll choose who to send it to.",
                reassurance: nil,
                placeholder: placeholder,
                softStarter: nil
            )
        case .directed:
            return Pack(
                experiment: experimentKey,
                family: family,
                variant: variant,
                bannerTitle: "Who made today a little better?",
                bannerBody: "A short note is enough — name optional for now.",
                reassurance: nil,
                placeholder: placeholder,
                softStarter: nil
            )
        case .softStart:
            return Pack(
                experiment: experimentKey,
                family: family,
                variant: variant,
                bannerTitle: "Who made today a little better?",
                bannerBody: "A short note is enough — name optional for now.",
                reassurance: nil,
                placeholder: placeholder,
                softStarter: "Thank you for — "
            )
        }
    }

    private static func campaignPack(variant: Variant, placeholder: String) -> Pack {
        // Day ask stays in `campaignHint`; variants only change coach chrome.
        switch variant {
        case .control:
            return Pack(
                experiment: experimentKey,
                family: .campaign,
                variant: variant,
                bannerTitle: nil,
                bannerBody: nil,
                reassurance: nil,
                placeholder: placeholder,
                softStarter: nil
            )
        case .directed:
            return Pack(
                experiment: experimentKey,
                family: .campaign,
                variant: variant,
                bannerTitle: nil,
                bannerBody: nil,
                reassurance: nil,
                placeholder: placeholder,
                softStarter: nil
            )
        case .softStart:
            return Pack(
                experiment: experimentKey,
                family: .campaign,
                variant: variant,
                bannerTitle: nil,
                bannerBody: nil,
                reassurance: nil,
                placeholder: placeholder,
                softStarter: "Thank you for — "
            )
        }
    }

    // MARK: - Hash / install id

    private static func stableDistinctId(
        _ distinctId: String?,
        defaults: UserDefaults
    ) -> String {
        let trimmed = distinctId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        if let existing = defaults.string(forKey: installIdKey), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: installIdKey)
        return fresh
    }

    /// FNV-1a 64-bit — stable across launches; not cryptographic.
    static func stableHash(_ string: String) -> UInt64 {
        let prime: UInt64 = 1099511628211
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
