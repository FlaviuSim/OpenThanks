import AppIntents
import Foundation
import UserNotifications

// MARK: - Spoken snippet → message draft (never the To field)

/// Freeform speech captured from a Siri phrase slot (App Shortcuts require AppEntity).
struct SpokenPhraseEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Details")
    static var defaultQuery = SpokenPhraseQuery()

    /// Same as `text` so `entities(for:)` always round-trips.
    var id: String
    var text: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(text)")
    }
}

struct SpokenPhraseQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SpokenPhraseEntity] {
        // Never return empty — empty results make Siri re-ask in a loop.
        identifiers.map { id in
            let text = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return SpokenPhraseEntity(id: id, text: text.isEmpty ? id : text)
        }
    }

    func entities(matching string: String) async throws -> [SpokenPhraseEntity] {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return [SpokenPhraseEntity(id: text, text: text)]
    }

    func suggestedEntities() async throws -> [SpokenPhraseEntity] {
        []
    }
}

enum SiriMessageDraft {
    /// Turns spoken phrase content into compose **message** text (To stays empty).
    static func fromSpoken(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if looksLikeName(text) {
            let name = softNameCase(text)
            // Open-ended so they can keep writing after the name.
            return "Thank you, \(name). "
        }

        let lower = text.lowercased()
        if lower.hasPrefix("thank") {
            return ensureEnding(text)
        }
        if lower.hasPrefix("for ") {
            return ensureEnding("Thank you \(text)")
        }
        return ensureEnding("Thank you for \(text)")
    }

    /// Short, name-like phrases (Maria, James, my mom) — not full sentences.
    static func looksLikeName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard (1...4).contains(words.count), trimmed.count <= 48 else { return false }

        let bannedChars = CharacterSet(charactersIn: "@#/:\\n")
        if trimmed.unicodeScalars.contains(where: { bannedChars.contains($0) }) { return false }
        if trimmed.contains("http") { return false }

        let lower = trimmed.lowercased()
        let notNames = [
            "someone", "somebody", "anyone", "everybody", "everyone",
            "appreciation", "thanks", "thank you",
        ]
        if notNames.contains(lower) { return false }

        // Full thoughts belong in the message body as-is (with thank-you framing).
        let sentenceHints = [" because ", " when ", " after ", " for helping", " for being", " who "]
        if sentenceHints.contains(where: { lower.contains($0) }) { return false }
        if lower.hasPrefix("for ") { return false }

        return true
    }

    private static func softNameCase(_ text: String) -> String {
        text.split(separator: " ").map { word -> String in
            let w = String(word)
            let lower = w.lowercased()
            // Keep small words lowercase unless first.
            if ["and", "of", "the", "da", "de", "van", "von"].contains(lower) {
                return lower
            }
            guard let first = w.first else { return w }
            return String(first).uppercased() + w.dropFirst().lowercased()
        }
        .joined(separator: " ")
    }

    private static func ensureEnding(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return t }
        if ".!?".contains(last) { return t + " " }
        return t + ". "
    }
}

// MARK: - Open blank compose

struct OpenComposeIntent: AppIntent {
    static var title: LocalizedStringResource = "Send an Appreciation"
    static var description = IntentDescription(
        "Opens OpenThanks to a new blank appreciation."
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        ComposeLaunchBridge.shared.queue()
        return .result(dialog: "Opening OpenThanks.")
    }
}

// MARK: - Phrase → message draft (To left blank)

/// Spoken details become the **message**, never the recipient field.
struct DraftAppreciationIntent: AppIntent {
    static var title: LocalizedStringResource = "Draft an Appreciation"
    static var description = IntentDescription(
        "Opens OpenThanks with a message draft from what you said."
    )
    static var openAppWhenRun = true

    @Parameter(title: "Details")
    var phrase: SpokenPhraseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Draft an appreciation about \(\.$phrase)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = SiriMessageDraft.fromSpoken(phrase.text)
        // Intentionally no recipientName / profile — user picks To in-app.
        ComposeLaunchBridge.shared.queue(message: draft)
        return .result(dialog: "Opening OpenThanks.")
    }
}

/// Older shortcut name — same as draft intent when a phrase is present.
struct ThankSomeoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Thank Someone on OpenThanks"
    static var description = IntentDescription(
        "Opens OpenThanks with a thank-you message draft."
    )
    static var openAppWhenRun = true

    @Parameter(title: "Details")
    var phrase: SpokenPhraseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Thank \(\.$phrase) on OpenThanks")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = SiriMessageDraft.fromSpoken(phrase.text)
        ComposeLaunchBridge.shared.queue(message: draft)
        return .result(dialog: "Opening OpenThanks.")
    }
}

struct CreateAppreciationIntent: AppIntent {
    static var title: LocalizedStringResource = "Create an OpenThanks Appreciation"
    static var description = IntentDescription(
        "Opens OpenThanks with a message draft."
    )
    static var openAppWhenRun = true

    @Parameter(title: "Details")
    var phrase: SpokenPhraseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Create an OpenThanks post about \(\.$phrase)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = SiriMessageDraft.fromSpoken(phrase.text)
        ComposeLaunchBridge.shared.queue(message: draft)
        return .result(dialog: "Opening OpenThanks.")
    }
}

struct RemindToThankIntent: AppIntent {
    static var title: LocalizedStringResource = "Remind Me to Thank Someone"
    static var description = IntentDescription(
        "Sets a reminder to thank someone on OpenThanks."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Name")
    var person: String

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
        let name = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 1 else {
            throw $person.needsValueError(IntentDialog("Who should I remind you to thank?"))
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

// MARK: - Shortcuts

struct OpenThanksShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        // No slots — always blank compose, no follow-up.
        AppShortcut(
            intent: OpenComposeIntent(),
            phrases: [
                "Send an appreciation on \(.applicationName)",
                "Create an appreciation on \(.applicationName)",
                "Write an appreciation on \(.applicationName)",
                "New appreciation on \(.applicationName)",
                "Create an \(.applicationName) post",
                "Open \(.applicationName) to say thanks",
                "Start an appreciation on \(.applicationName)",
                "Thank someone on \(.applicationName)",
                "Send thanks on \(.applicationName)",
                "Appreciate someone on \(.applicationName)",
                "Create an \(.applicationName) appreciation",
                "New \(.applicationName) appreciation",
            ],
            shortTitle: "Send appreciation",
            systemImageName: "heart.fill"
        )

        // Spoken details → message body (To stays empty).
        AppShortcut(
            intent: DraftAppreciationIntent(),
            phrases: [
                "Thank \(\.$phrase) on \(.applicationName)",
                "Send thanks to \(\.$phrase) on \(.applicationName)",
                "Appreciate \(\.$phrase) on \(.applicationName)",
                "Create an \(.applicationName) post for \(\.$phrase)",
                "New \(.applicationName) appreciation for \(\.$phrase)",
                "Write an appreciation for \(\.$phrase) on \(.applicationName)",
                "Draft an appreciation for \(\.$phrase) on \(.applicationName)",
            ],
            shortTitle: "Draft appreciation",
            systemImageName: "text.badge.plus"
        )
    }
}
