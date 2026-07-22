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
        let pendingCount: Int
        if let pendingToAccept {
            pendingCount = pendingToAccept
        } else {
            pendingCount = (try? await GratitudeService.pendingToAcceptCount(
                userId: userId,
                email: email,
                phone: phone
            )) ?? previous.pendingToAccept
        }

        let sentMonth = (try? await month) ?? previous.sentThisMonth
        let profileStats = await stats

        let snapshot = WidgetSnapshot(
            displayName: displayName,
            sentThisMonth: sentMonth,
            receivedTotal: profileStats?.received ?? previous.receivedTotal,
            pendingToAccept: pendingCount,
            updatedAt: .now
        )
        WidgetSnapshotStore.save(snapshot)
    }

    static func clear() {
        WidgetSnapshotStore.clear()
    }
}
