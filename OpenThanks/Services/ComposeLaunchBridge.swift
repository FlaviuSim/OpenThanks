import Foundation
import Observation

extension Notification.Name {
    static let composeLaunchQueued = Notification.Name("openthanks.composeLaunchQueued")
    static let focusReceivedThanks = Notification.Name("openthanks.focusReceivedThanks")
    /// Tear down share / nudge sheets before opening compose from a notification.
    static let dismissTransientSheets = Notification.Name("openthanks.dismissTransientSheets")
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
        /// PostHog compose funnel `source`.
        var analyticsSource: String

        init(
            id: UUID = UUID(),
            recipientName: String? = nil,
            message: String? = nil,
            messagePlaceholder: String? = nil,
            profile: Profile? = nil,
            imageFileName: String? = nil,
            inspiredByGratitudeId: UUID? = nil,
            inspiredByAuthorName: String? = nil,
            analyticsSource: String = "compose_launch"
        ) {
            self.id = id
            self.recipientName = recipientName
            self.message = message
            self.messagePlaceholder = messagePlaceholder
            self.profile = profile
            self.imageFileName = imageFileName
            self.inspiredByGratitudeId = inspiredByGratitudeId
            self.inspiredByAuthorName = inspiredByAuthorName
            self.analyticsSource = analyticsSource
        }

        /// Blank cold-start / icon-open compose — must lose to notification / calendar / share launches.
        var isWeakDefault: Bool {
            analyticsSource == "app_open"
                && recipientName == nil
                && message == nil
                && messagePlaceholder == nil
                && profile == nil
                && imageFileName == nil
                && inspiredByGratitudeId == nil
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
        analyticsSource: String = "compose_launch"
    ) {
        let trimmedName = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlaceholder = messagePlaceholder?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImage = imageFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInspiredName = inspiredByAuthorName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let request = Request(
            recipientName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            message: (trimmedMessage?.isEmpty == false) ? trimmedMessage : nil,
            messagePlaceholder: (trimmedPlaceholder?.isEmpty == false) ? trimmedPlaceholder : nil,
            profile: profile,
            imageFileName: (trimmedImage?.isEmpty == false) ? trimmedImage : nil,
            inspiredByGratitudeId: inspiredByGratitudeId,
            inspiredByAuthorName: (trimmedInspiredName?.isEmpty == false) ? trimmedInspiredName : nil,
            analyticsSource: analyticsSource
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
