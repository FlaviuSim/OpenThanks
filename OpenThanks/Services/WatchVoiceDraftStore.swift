import Foundation
import UIKit
import UserNotifications

/// Holds a Watch voice draft until the user finishes (or dismisses) the first review.
///
/// Flow:
/// 1. Transcription finishes → create a **pending** appreciation on the server, then open Compose.
/// 2. First app open restores Compose only while a local “needs review” draft remains.
/// 3. Cancel / swipe-dismiss / Save clears the local draft so Compose does **not** auto-open again.
///    The pending appreciation stays in Pending Appreciations.
enum WatchVoiceDraftStore {
    private static let defaultsKey = "openthanks.watchVoiceDraft.v1"
    static let notificationTypeValue = "watch_voice_draft"
    private static let notificationId = "watch-voice-draft"

    struct Draft: Codable, Equatable {
        var id: UUID
        var message: String
        var createdAt: Date
        /// Server pending appreciation created when the Watch audio was polished.
        var gratitudeId: UUID?
    }

    static func save(_ draft: Draft) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load() -> Draft? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let draft = try? JSONDecoder().decode(Draft.self, from: data)
        else { return nil }
        let trimmed = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return nil
        }
        return draft
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationId])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    /// Call when the user leaves the Watch review sheet (Cancel, swipe, or Save).
    /// Clears local auto-present state; the server pending row is kept.
    @MainActor
    static func finishReviewSession(authorId: UUID?) async {
        guard let draft = load() else { return }
        // Legacy / offline: never created a pending row — save one so Cancel
        // still leaves something findable under Pending Appreciations.
        if draft.gratitudeId == nil, let authorId {
            let trimmed = draft.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let new = NewGratitude(
                    authorId: authorId,
                    message: trimmed,
                    recipientEmail: nil,
                    recipientPhone: nil,
                    recipientName: nil,
                    recipientId: nil,
                    visibility: GratitudeVisibility.public.rawValue,
                    mediaUrl: nil,
                    mediaType: nil,
                    source: "watch"
                )
                if let created = try? await GratitudeService.create(new) {
                    Analytics.appreciationSubmitted(
                        hasMedia: false,
                        messageLength: trimmed.count,
                        hasRecipient: false,
                        toMember: false,
                        recipientType: "none",
                        visibility: GratitudeVisibility.public.rawValue,
                        source: "watch"
                    )
                    await WidgetSnapshotRefresher.refresh(
                        displayName: nil,
                        userId: authorId,
                        email: nil,
                        phone: nil
                    )
                    _ = created
                }
            }
        }
        clear()
    }

    /// Create pending + queue compose (+ optional banner when phone isn't foregrounded).
    @MainActor
    static func presentForReview(message: String, draftId: UUID, authorId: UUID) async {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        // Idempotent if the same Watch draft is delivered twice.
        if let existing = load(), existing.id == draftId {
            await queueCompose(for: existing)
            await notifyIfNeeded(draftId: draftId)
            return
        }

        let new = NewGratitude(
            authorId: authorId,
            message: cleaned,
            recipientEmail: nil,
            recipientPhone: nil,
            recipientName: nil,
            recipientId: nil,
            visibility: GratitudeVisibility.public.rawValue,
            mediaUrl: nil,
            mediaType: nil,
            source: "watch"
        )

        do {
            let created = try await GratitudeService.create(new)
            Analytics.appreciationSubmitted(
                hasMedia: false,
                messageLength: cleaned.count,
                hasRecipient: false,
                toMember: false,
                recipientType: "none",
                visibility: GratitudeVisibility.public.rawValue,
                source: "watch"
            )
            await WidgetSnapshotRefresher.refresh(
                displayName: nil,
                userId: authorId,
                email: nil,
                phone: nil
            )
            await StreakLiveActivityController.appreciationDidSend(userId: authorId)

            let draft = Draft(
                id: draftId,
                message: cleaned,
                createdAt: .now,
                gratitudeId: created.id
            )
            save(draft)
            ComposeLaunchBridge.shared.queue(
                message: cleaned,
                analyticsSource: "watch",
                allowsEmptyRecipient: true,
                editingGratitude: created
            )
        } catch {
            // Still open compose; Cancel/Save will persist via finishReviewSession / create.
            let draft = Draft(
                id: draftId,
                message: cleaned,
                createdAt: .now,
                gratitudeId: nil
            )
            save(draft)
            ComposeLaunchBridge.shared.queue(
                message: cleaned,
                analyticsSource: "watch",
                allowsEmptyRecipient: true
            )
            Analytics.appreciationFailed(error: error.localizedDescription, source: "watch")
        }

        await notifyIfNeeded(draftId: draftId)
    }

    /// Cold start / resume: re-queue only while a local review draft still exists.
    @MainActor
    static func restorePendingComposeIfNeeded() async {
        guard let draft = load() else { return }
        if let pending = ComposeLaunchBridge.shared.pending,
           pending.analyticsSource == "watch" {
            return
        }
        await queueCompose(for: draft)
    }

    @MainActor
    private static func queueCompose(for draft: Draft) async {
        if let pending = ComposeLaunchBridge.shared.pending,
           pending.analyticsSource == "watch" {
            return
        }
        var editing: Gratitude?
        if let gratitudeId = draft.gratitudeId {
            editing = try? await GratitudeService.gratitude(id: gratitudeId)
            // Cancelled while fetching — do not reopen.
            guard load()?.id == draft.id else { return }
        }
        ComposeLaunchBridge.shared.queue(
            message: draft.message,
            analyticsSource: "watch",
            allowsEmptyRecipient: true,
            editingGratitude: editing
        )
    }

    private static func notifyIfNeeded(draftId: UUID) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        if await MainActor.run(body: { UIApplication.shared.applicationState == .active }) {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Finish your Watch thanks"
        content.body = "Saved to Pending — add who it’s for when you’re ready."
        content.sound = .default
        content.userInfo = [
            NotificationService.thankReminderTypeKey: notificationTypeValue,
            "draftId": draftId.uuidString,
        ]

        let request = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
