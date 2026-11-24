import Foundation
import Observation

extension Notification.Name {
    static let composeLaunchQueued = Notification.Name("openthanks.composeLaunchQueued")
    static let focusReceivedThanks = Notification.Name("openthanks.focusReceivedThanks")
    /// Tear down share / nudge sheets before opening compose from a notification.
    static let dismissTransientSheets = Notification.Name("openthanks.dismissTransientSheets")
    /// Home feed posts pending-to-accept count so first-send coachmark can wait.
    static let homePendingAcceptCount = Notification.Name("openthanks.homePendingAcceptCount")
    /// `userInfo["presented"]` is true from the moment an accept will show the
    /// ripple sheet (including the short settle delay) until that sheet closes.
    static let payItForwardSheetPresented = Notification.Name("openthanks.payItForwardSheetPresented")
    /// Reload My Feed pending cards (push arrived, Home selected, World refresh).
    static let pendingThanksShouldRefresh = Notification.Name("openthanks.pendingThanksShouldRefresh")
    /// Inbox / bell badge should refetch (accept, accept-privately, decline).
    static let notificationsShouldRefresh = Notification.Name("openthanks.notificationsShouldRefresh")
}

/// Queues a compose sheet from Siri / App Intents / widgets / Share Extension.
@Observable
@MainActor
final class ComposeLaunchBridge {
    static let shared = ComposeLaunchBridge()

    struct Request: Identifiable, Equatable {
        let id: UUID
        var recipientName: String?
        var message: String?
        /// Empty-field placeholder (e.g. Friday prompt starter idea).
        var messagePlaceholder: String?
        /// When set, compose links the member chip instead of free text.
        var profile: Profile?
        /// App Group ShareInbox filename to attach as the post photo.
        var imageFileName: String?
        /// Parent appreciation for pay-it-forward / ripple attribution.
        var inspiredByGratitudeId: UUID?
        /// Display name for inspired-by placeholder copy.
        var inspiredByAuthorName: String?
        /// Prompt shown above the message field. Does not prefill the message.
        var campaignHint: String?
        /// PostHog `campaign` when this compose was opened from a prompt.
        var campaignId: String?
        /// PostHog `campaign_day`.
        var campaignDay: Int?
        /// PostHog compose funnel `source`.
        var analyticsSource: String
        /// Watch / unfinished pending: write → deliver. Blank compose stays one page.
        var allowsEmptyRecipient: Bool
        /// Watch voice / pending: edit the pending appreciation that was auto-created.
        var editingGratitude: Gratitude?
        /// Open on the post-save deliver / share screen for an existing draft.
        var opensOnShareScreen: Bool

        init(
            id: UUID = UUID(),
            recipientName: String? = nil,
            message: String? = nil,
            messagePlaceholder: String? = nil,
            profile: Profile? = nil,
            imageFileName: String? = nil,
            inspiredByGratitudeId: UUID? = nil,
            inspiredByAuthorName: String? = nil,
            campaignHint: String? = nil,
            campaignId: String? = nil,
            campaignDay: Int? = nil,
            analyticsSource: String = "compose_launch",
            allowsEmptyRecipient: Bool = false,
            editingGratitude: Gratitude? = nil,
            opensOnShareScreen: Bool = false
        ) {
            self.id = id
            self.recipientName = recipientName
            self.message = message
            self.messagePlaceholder = messagePlaceholder
            self.profile = profile
            self.imageFileName = imageFileName
            self.inspiredByGratitudeId = inspiredByGratitudeId
            self.inspiredByAuthorName = inspiredByAuthorName
            self.campaignHint = campaignHint
            self.campaignId = campaignId
            self.campaignDay = campaignDay
            self.analyticsSource = analyticsSource
            self.editingGratitude = editingGratitude
            self.opensOnShareScreen = opensOnShareScreen
            // Blank compose is one page (To at top). Two-step only for Watch and
            // unfinished pending / share-screen opens.
            self.allowsEmptyRecipient = Self.resolveAllowsEmptyRecipient(
                explicit: allowsEmptyRecipient,
                editingGratitude: editingGratitude,
                analyticsSource: analyticsSource,
                opensOnShareScreen: opensOnShareScreen
            )
        }

        /// True for write → deliver (Watch / unfinished pending). Blank FAB is false.
        static func resolveAllowsEmptyRecipient(
            explicit: Bool = false,
            recipientName: String? = nil,
            profile: Profile? = nil,
            editingGratitude: Gratitude? = nil,
            analyticsSource: String? = nil,
            opensOnShareScreen: Bool = false
        ) -> Bool {
            // Prefill args kept for call-site compatibility; blank compose no longer
            // flips two-step just because To is empty.
            let _ = (recipientName, profile)
            if analyticsSource == "watch" { return true }
            if let editing = editingGratitude, editing.hasNoRecipient { return true }
            if opensOnShareScreen, editingGratitude?.hasNoRecipient != false { return true }
            return explicit
        }

        /// Blank post-login / legacy app_open compose — richer launches replace these.
        var isWeakDefault: Bool {
            (analyticsSource == "app_open" || analyticsSource == "post_login")
                && recipientName == nil
                && message == nil
                && messagePlaceholder == nil
                && profile == nil
                && imageFileName == nil
                && inspiredByGratitudeId == nil
                && campaignHint == nil
                && campaignId == nil
                && editingGratitude == nil
        }
    }

    private(set) var pending: Request?

    func queue(
        recipientName: String? = nil,
        message: String? = nil,
        messagePlaceholder: String? = nil,
        profile: Profile? = nil,
        imageFileName: String? = nil,
        inspiredByGratitudeId: UUID? = nil,
        inspiredByAuthorName: String? = nil,
        campaignHint: String? = nil,
        campaignId: String? = nil,
        campaignDay: Int? = nil,
        analyticsSource: String = "compose_launch",
        allowsEmptyRecipient: Bool = false,
        editingGratitude: Gratitude? = nil,
        opensOnShareScreen: Bool = false
    ) {
        let trimmedName = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlaceholder = messagePlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImage = imageFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInspiredName = inspiredByAuthorName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHint = campaignHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCampaign = campaignId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(
            recipientName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            message: (trimmedMessage?.isEmpty == false) ? trimmedMessage : nil,
            messagePlaceholder: (trimmedPlaceholder?.isEmpty == false) ? trimmedPlaceholder : nil,
            profile: profile,
            imageFileName: (trimmedImage?.isEmpty == false) ? trimmedImage : nil,
            inspiredByGratitudeId: inspiredByGratitudeId,
            inspiredByAuthorName: (trimmedInspiredName?.isEmpty == false) ? trimmedInspiredName : nil,
            campaignHint: (trimmedHint?.isEmpty == false) ? trimmedHint : nil,
            campaignId: (trimmedCampaign?.isEmpty == false) ? trimmedCampaign : nil,
            campaignDay: campaignDay,
            analyticsSource: analyticsSource,
            allowsEmptyRecipient: allowsEmptyRecipient,
            editingGratitude: editingGratitude,
            opensOnShareScreen: opensOnShareScreen
        )
        // Never let blank app_open clobber a calendar / notification / share prefill
        // that landed milliseconds earlier on cold start.
        if let pending, !pending.isWeakDefault, request.isWeakDefault {
            return
        }
        pending = request
        NotificationCenter.default.post(name: .composeLaunchQueued, object: nil)
    }

    func consume() -> Request? {
        let next = pending
        pending = nil
        return next
    }
}
