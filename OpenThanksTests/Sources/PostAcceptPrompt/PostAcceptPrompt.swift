import Foundation

/// Paths on the post-accept chooser (who to thank next).
enum PostAcceptPath: String, CaseIterable, Identifiable, Sendable {
    case helpedThisWeek
    case neverThanked
    case echoGift
    case calendarPerson
    case calendarConnect
    case remindTonight

    var id: String { rawValue }

    /// Chip / row label.
    var chipTitle: String {
        switch self {
        case .helpedThisWeek: return "Someone who helped me this week"
        case .neverThanked: return "Someone I’ve never properly thanked"
        case .echoGift: return "Someone like that for me"
        case .calendarPerson: return "Someone from today"
        case .calendarConnect: return "Suggest from my calendar"
        case .remindTonight: return "Remind me tonight"
        }
    }
}

/// One concrete next step from the post-accept sheet.
struct PostAcceptChoice: Equatable, Sendable {
    var path: PostAcceptPath
    /// Prefills To when known (calendar face, etc.).
    var recipientName: String? = nil
    var recipientEmail: String? = nil
    /// Soft starter in the message field.
    var message: String
    /// Optional meeting title for analytics / draft context.
    var meetingTitle: String? = nil
}

/// Lightweight theme mirrored from the note they just accepted.
enum GratitudeEchoTheme: String, Equatable, Sendable {
    case jumpingIn
    case listening
    case believing
    case teaching
    case showingUp
    case general

    /// Question chip line shown when this theme is detected.
    var question: String {
        switch self {
        case .jumpingIn: return "Who’s jumped in for you lately?"
        case .listening: return "Who’s really listened to you lately?"
        case .believing: return "Who’s believed in you lately?"
        case .teaching: return "Who’s taught you something lately?"
        case .showingUp: return "Who’s shown up for you lately?"
        case .general: return "Who’s shaped you lately?"
        }
    }

    var starterMessage: String {
        switch self {
        case .jumpingIn: return "Thank you for jumping in when I needed it — "
        case .listening: return "Thank you for really listening — "
        case .believing: return "Thank you for believing in me — "
        case .teaching: return "Thank you for teaching me — "
        case .showingUp: return "Thank you for showing up — "
        case .general: return "Thank you for — "
        }
    }

    /// Best-effort keyword match on the accepted appreciation.
    static func detect(from message: String?) -> GratitudeEchoTheme {
        let text = (message ?? "").lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .general
        }
        if matches(text, ["jump", "stuck", "bail", "cover for", "stepped in", "helped me out"]) {
            return .jumpingIn
        }
        if matches(text, ["listen", "heard me", "talk through", "vent"]) {
            return .listening
        }
        if matches(text, ["believe", "encourag", "cheer", "had my back", "supported me"]) {
            return .believing
        }
        if matches(text, ["teach", "taught", "showed me", "explain", "mentor", "coach"]) {
            return .teaching
        }
        if matches(text, ["show up", "showed up", "there for me", "checked in", "by my side"]) {
            return .showingUp
        }
        return .general
    }

    private static func matches(_ text: String, _ tokens: [String]) -> Bool {
        tokens.contains { text.contains($0) }
    }
}

/// Copy + starters for the post-accept ripple sheet. Actions stay on the view.
enum PayItForwardPromptCopy {
    static let body = "Pass the warmth on — pick who comes to mind. A short note is enough."
    static let reassurance = "Don’t worry about the wording. They’ll love that you thought of them."
    static let primaryButton = "Send a note"
    static let notNow = "Not now"
    static let choosePrompt = "Who will you thank?"
    static let calendarSection = "From today’s meetings"
    static let calendarEmpty = "No clear meeting faces yet today."
    static let remindDetail = "We’ll nudge you this evening with a blank note ready."

    /// First word of the sender's name, matching the previous sheet.
    static func firstName(from fromName: String?) -> String {
        guard let fromName else { return "someone" }
        let trimmed = fromName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "someone" }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    static func title(fromName: String?) -> String {
        "\(firstName(from: fromName)) thanked you"
    }

    static func starter(
        for path: PostAcceptPath,
        echoTheme: GratitudeEchoTheme = .general,
        personName: String? = nil
    ) -> String {
        switch path {
        case .helpedThisWeek:
            return "Thank you for helping me this week — "
        case .neverThanked:
            return "I’ve never properly thanked you for — "
        case .echoGift:
            return echoTheme.starterMessage
        case .calendarPerson:
            if let personName, !personName.isEmpty {
                let first = firstName(from: personName)
                return "Thank you for meeting today, \(first) — "
            }
            return "Thank you for meeting with me today — "
        case .calendarConnect, .remindTonight:
            return "Thank you for — "
        }
    }

    static func choice(
        path: PostAcceptPath,
        echoTheme: GratitudeEchoTheme = .general,
        recipientName: String? = nil,
        recipientEmail: String? = nil,
        meetingTitle: String? = nil,
        messageOverride: String? = nil
    ) -> PostAcceptChoice {
        let message = messageOverride
            ?? starter(for: path, echoTheme: echoTheme, personName: recipientName)
        return PostAcceptChoice(
            path: path,
            recipientName: recipientName,
            recipientEmail: recipientEmail,
            message: message,
            meetingTitle: meetingTitle
        )
    }

    /// Question chips shown above calendar / remind (always includes week + never).
    static func questionPaths(echoTheme: GratitudeEchoTheme) -> [PostAcceptPath] {
        var paths: [PostAcceptPath] = [.helpedThisWeek, .neverThanked]
        if echoTheme != .general {
            paths.append(.echoGift)
        }
        return paths
    }

    static func chipTitle(for path: PostAcceptPath, echoTheme: GratitudeEchoTheme) -> String {
        if path == .echoGift { return echoTheme.question }
        return path.chipTitle
    }
}

/// Home coachmark above the compose FAB.
enum FirstSendTip {
    static let title = "The + button starts a note"
    static let detail = "Tap it when you know who it's for."

    /// Set when any composer is opened. Separate from `hasSeenFirstSendTip`,
    /// which still means the person dismissed or tapped the tip itself.
    static let composerOpenedKey = "firstSendTip.hasOpenedComposer"
    static let composerOpened = Notification.Name("openthanks.firstSendTipComposerOpened")

    static func hasOpenedComposer(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: composerOpenedKey)
    }

    static func markComposerOpened(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: composerOpenedKey)
        NotificationCenter.default.post(name: composerOpened, object: nil)
    }

    /// Retired — the Home “+ button starts a note” coachmark is no longer shown.
    static func shouldShow(
        hasSeenTip: Bool,
        isFeedTab: Bool,
        tabComposerPresented: Bool,
        searchActive: Bool,
        pendingAcceptCount: Int,
        rippleSheetPresented: Bool,
        hasOpenedComposer: Bool,
        hasSentAppreciation: Bool
    ) -> Bool {
        false
    }
}
