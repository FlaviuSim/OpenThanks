import Foundation
import Observation

extension Notification.Name {
    static let composeLaunchQueued = Notification.Name("openthanks.composeLaunchQueued")
    static let focusReceivedThanks = Notification.Name("openthanks.focusReceivedThanks")
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
        /// When set, compose links the member chip instead of free text.
        var profile: Profile?
        /// App Group ShareInbox filename to attach as the post photo.
        var imageFileName: String?
        /// PostHog compose funnel `source`.
        var analyticsSource: String

        init(
            id: UUID = UUID(),
            recipientName: String? = nil,
            message: String? = nil,
            profile: Profile? = nil,
            imageFileName: String? = nil,
            analyticsSource: String = "compose_launch"
        ) {
            self.id = id
            self.recipientName = recipientName
            self.message = message
            self.profile = profile
            self.imageFileName = imageFileName
            self.analyticsSource = analyticsSource
        }
    }

    private(set) var pending: Request?

    func queue(
        recipientName: String? = nil,
        message: String? = nil,
        profile: Profile? = nil,
        imageFileName: String? = nil,
        analyticsSource: String = "compose_launch"
    ) {
        let trimmedName = recipientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedImage = imageFileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = Request(
            recipientName: (trimmedName?.isEmpty == false) ? trimmedName : nil,
            message: (trimmedMessage?.isEmpty == false) ? trimmedMessage : nil,
            profile: profile,
            imageFileName: (trimmedImage?.isEmpty == false) ? trimmedImage : nil,
            analyticsSource: analyticsSource
        )
        NotificationCenter.default.post(name: .composeLaunchQueued, object: nil)
    }

    func consume() -> Request? {
        let next = pending
        pending = nil
        return next
    }
}
