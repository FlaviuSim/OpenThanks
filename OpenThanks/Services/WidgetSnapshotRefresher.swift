import Foundation
import WidgetKit

/// Writes an offline snapshot for Home / Lock Screen widgets after feed or profile loads.
enum WidgetSnapshotRefresher {
    @MainActor
    static func refresh(
        displayName: String?,
        userId: UUID,
        email: String? = nil,
        phone: String? = nil,
        pendingToAccept: Int? = nil
    ) async {
        let previous = WidgetSnapshotStore.load()
        async let month = GratitudeService.sentThisMonth(authorId: userId)
        async let stats = try? GratitudeService.stats(userId: userId)
        async let pendingRows = try? GratitudeService.pendingToAccept(
            userId: userId,
            email: email,
            phone: phone
        )
        async let recentAccepted = try? GratitudeService.receivedBy(
            userId: userId,
            viewerId: userId,
            limit: 1
        )

        let pendingList = await pendingRows ?? []
        let pendingCount = pendingToAccept ?? pendingList.count
        let sentMonth = (try? await month) ?? previous.sentThisMonth
        let profileStats = await stats
        let accepted = await recentAccepted ?? []

        let latestReceived = Self.makeTeaser(pending: pendingList, accepted: accepted)
            ?? previous.latestReceived

        let snapshot = WidgetSnapshot(
            displayName: displayName,
            sentThisMonth: sentMonth,
            receivedTotal: profileStats?.received ?? previous.receivedTotal,
            pendingToAccept: pendingCount,
            latestReceived: latestReceived,
            updatedAt: .now
        )
        WidgetSnapshotStore.save(snapshot)
    }

    static func clear() {
        WidgetSnapshotStore.clear()
    }

    private static func makeTeaser(
        pending: [Gratitude],
        accepted: [Gratitude]
    ) -> WidgetReceivedTeaser? {
        let source = pending.first ?? accepted.first
        guard let gratitude = source else { return nil }
        let preview = WidgetReceivedTeaser.preview(from: gratitude.message)
        guard !preview.isEmpty else { return nil }
        let fromName = gratitude.author?.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = (fromName?.isEmpty == false) ? fromName! : "Someone"
        return WidgetReceivedTeaser(
            gratitudeId: gratitude.id,
            fromName: display,
            messagePreview: preview,
            isPending: gratitude.status == .pending
        )
    }
}
