import AppIntents
import Foundation
import UserNotifications

// MARK: - Name helpers

enum SiriRecipientName {
    /// Phrases Siri often treats as “finished talking” — never use these as a person.
    private static let dismissalPhrases: Set<String> = [
        "all done", "done", "i'm done", "im done", "that's all", "thats all",
        "that is all", "finished", "finish", "stop", "cancel", "never mind",
        "nevermind", "no thanks", "nothing", "no one", "nobody", "okay", "ok",
        "yes", "no",
    ]

    static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        let lowered = trimmed.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)
        if dismissalPhrases.contains(lowered) { return nil }
        return trimmed
    }

    /// Stable entity id that round-trips through `entities(for:)`.
    static func entityId(for name: String) -> String {
        "n:\(name)"
    }

    static func name(fromEntityId id: String) -> String? {
        if id.hasPrefix("n:") {
            let name = String(id.dropFirst(2))
            return cleaned(name) ?? (name.isEmpty ? nil : name)
        }
        return cleaned(id)
    }
}

// MARK: - Person entity (required for App Shortcut phrase slots)

struct ThankRecipientEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Person")
    static var defaultQuery = ThankRecipientQuery()

    var id: String
    var name: String
    var profileId: UUID?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Freeform name query — returns **one** entity for whatever the user said.
/// Do not attach profile search hits here; multiple matches make Siri re-ask
/// “who?” in a loop (and “all done” can get captured as the name).
struct ThankRecipientQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ThankRecipientEntity] {
        identifiers.compactMap { id in
            if let name = SiriRecipientName.name(fromEntityId: id) {
                return ThankRecipientEntity(
                    id: SiriRecipientName.entityId(for: name),
                    name: name,
                    profileId: nil
                )
            }
            if let uuid = UUID(uuidString: id) {
                return ThankRecipientEntity(id: id, name: id, profileId: uuid)
            }
            return nil
        }
    }

    func entities(matching string: String) async throws -> [ThankRecipientEntity] {
        guard let name = SiriRecipientName.cleaned(string) else { return [] }
        return [
            ThankRecipientEntity(
                id: SiriRecipientName.entityId(for: name),
                name: name,
                profileId: nil
            ),
        ]
    }

    func suggestedEntities() async throws -> [ThankRecipientEntity] {
        []
    }
}

// MARK: - Thank someone (opens compose prefilled)

/// “Siri, thank Maria on OpenThanks for introducing me to John.”
struct ThankSomeoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Thank Someone on OpenThanks"
    static var description = IntentDescription(
        "Opens a new appreciation with a person and optional reason filled in."
    )
    static var openAppWhenRun = true

    /// No `requestValueDialog` — a custom dialog + AppEntity often loops in Siri.
    @Parameter(title: "Name")
    var person: ThankRecipientEntity

    @Parameter(title: "Reason")
    var reason: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Thank \(\.$person) on OpenThanks") {
            \.$reason
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let name = SiriRecipientName.cleaned(person.name) else {
            throw $person.needsValueError("Who do you want to thank?")
        }

        let draft: String? = {
            guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !reason.isEmpty
            else { return nil }
            if reason.lowercased().hasPrefix("for ") {
                return "Thank you \(reason)."
            }
            return "Thank you for \(reason)."
        }()

        var profile: Profile?
        if let id = person.profileId {
            profile = try? await GratitudeService.profile(id: id)
        }
        if profile == nil {
            profile = try? await resolveMember(named: name)
        }

        ComposeLaunchBridge.shared.queue(
            recipientName: name,
            message: draft,
            profile: profile
        )

        if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
            return .result(dialog: "Opening OpenThanks to thank \(name) for \(reason).")
        }
        return .result(dialog: "Opening OpenThanks to thank \(name).")
    }
}

// MARK: - Create a post

/// “Siri, create an OpenThanks post for my daughter’s teacher.”
struct CreateAppreciationIntent: AppIntent {
    static var title: LocalizedStringResource = "Create an OpenThanks Appreciation"
    static var description = IntentDescription(
        "Starts a new appreciation for someone you name."
    )
    static var openAppWhenRun = true

    @Parameter(title: "For")
    var person: ThankRecipientEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Create an OpenThanks post for \(\.$person)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let name = SiriRecipientName.cleaned(person.name) else {
            throw $person.needsValueError("Who is this appreciation for?")
        }

        var profile: Profile?
        if let id = person.profileId {
            profile = try? await GratitudeService.profile(id: id)
        }
        if profile == nil {
            profile = try? await resolveMember(named: name)
        }

        ComposeLaunchBridge.shared.queue(
            recipientName: name,
            message: nil,
            profile: profile
        )
        return .result(dialog: "Opening a new appreciation for \(name).")
    }
}

// MARK: - Remind me to thank

/// “Siri, remind me to thank James after the meeting.”
struct RemindToThankIntent: AppIntent {
    static var title: LocalizedStringResource = "Remind Me to Thank Someone"
    static var description = IntentDescription(
        "Sets a reminder to thank someone on OpenThanks."
    )
    /// Stay in Siri when possible — notification will reopen the app later.
    static var openAppWhenRun = false

    @Parameter(title: "Name")
    var person: ThankRecipientEntity

    @Parameter(
        title: "When",
        description: "If omitted, reminds you in one hour."
    )
    var when: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Remind me to thank \(\.$person)") {
            \.$when
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let name = SiriRecipientName.cleaned(person.name) else {
            throw $person.needsValueError("Who should I remind you to thank?")
        }

        let requested = when ?? Date().addingTimeInterval(60 * 60)
        let fireDate = max(requested, Date().addingTimeInterval(45))

        let granted = await NotificationService.requestAuthorizationAndRegisterForPushes()
        guard granted else {
            return .result(
                dialog: "Notifications are off. Enable them in Settings, then ask me again."
            )
        }

        try await NotificationService.scheduleThankReminder(
            recipientName: name,
            fireDate: fireDate
        )

        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let whenText = formatter.string(from: fireDate)
        return .result(dialog: "Okay — I'll remind you to thank \(name) \(whenText).")
    }
}

// MARK: - Shortcuts phrases (what Siri listens for)

struct OpenThanksShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ThankSomeoneIntent(),
            phrases: [
                "Thank \(\.$person) on \(.applicationName)",
                "Send thanks to \(\.$person) on \(.applicationName)",
                "Appreciate \(\.$person) on \(.applicationName)",
                "Thank someone on \(.applicationName)",
            ],
            shortTitle: "Thank someone",
            systemImageName: "heart.fill"
        )

        AppShortcut(
            intent: CreateAppreciationIntent(),
            phrases: [
                "Create an \(.applicationName) post for \(\.$person)",
                "New \(.applicationName) appreciation for \(\.$person)",
                "Write an appreciation for \(\.$person) on \(.applicationName)",
                "Create an \(.applicationName) post",
            ],
            shortTitle: "New appreciation",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: RemindToThankIntent(),
            phrases: [
                "Remind me to thank \(\.$person) on \(.applicationName)",
                "Set a reminder to thank \(\.$person) on \(.applicationName)",
                "Remind me to thank someone on \(.applicationName)",
            ],
            shortTitle: "Remind to thank",
            systemImageName: "bell.fill"
        )
    }
}

// MARK: - Helpers

private func resolveMember(named raw: String) async throws -> Profile? {
    let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard query.count >= 2 else { return nil }

    let handle = query.hasPrefix("@") ? String(query.dropFirst()) : query
    if let byUsername = try? await GratitudeService.profile(username: handle.lowercased()) {
        return byUsername
    }

    let results = try await GratitudeService.searchProfiles(query: handle, limit: 5)
    if results.count == 1 { return results[0] }

    let lowered = handle.lowercased()
    return results.first {
        $0.fullName?.lowercased() == lowered
            || $0.username.lowercased() == lowered
            || $0.displayName.lowercased() == lowered
    }
}
