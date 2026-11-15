import Foundation

/// Copy for the post-accept ripple sheet. Actions and analytics stay on the view.
enum PayItForwardPromptCopy {
    static let body = "Send one note to someone else, if you want their kindness to keep going."
    static let primaryButton = "Send a note"
    static let notNow = "Not now"

    /// First word of the sender's name, matching the previous sheet.
    static func firstName(from fromName: String?) -> String {
        guard let fromName, !fromName.isEmpty else { return "someone" }
        return fromName.split(separator: " ").first.map(String.init) ?? fromName
    }

    static func title(fromName: String?) -> String {
        "\(firstName(from: fromName)) thanked you"
    }
}

/// Home coachmark above the heart button.
enum FirstSendTip {
    static let title = "The heart below starts a note"
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

    /// The tip sits on the Home tab bar. Hide it under the ripple sheet, and
    /// hide it once this device has opened the composer or sent a note.
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
        !hasSeenTip
            && isFeedTab
            && !tabComposerPresented
            && !searchActive
            && pendingAcceptCount == 0
            && !rippleSheetPresented
            && !hasOpenedComposer
            && !hasSentAppreciation
    }
}
