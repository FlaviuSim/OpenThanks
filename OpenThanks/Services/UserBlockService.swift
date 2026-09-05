import Foundation
import Observation

/// Client-side user blocks (App Store Guideline 1.2 — pair with Report).
/// Cached in memory after login; filtered from feeds/search by callers.
@Observable
@MainActor
final class UserBlockService {
    private(set) var blockedIds: Set<UUID> = []
    private(set) var isLoading = false

    enum BlockError: LocalizedError {
        case notSignedIn
        case cannotBlockSelf
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                "Sign in to block someone."
            case .cannotBlockSelf:
                "You can’t block yourself."
            case .server(let message):
                message
            }
        }
    }

    private struct BlockRow: Decodable {
        let blockedId: UUID

        enum CodingKeys: String, CodingKey {
            case blockedId = "blocked_id"
        }
    }

    private struct BlockInsert: Encodable {
        let blockerId: UUID
        let blockedId: UUID

        enum CodingKeys: String, CodingKey {
            case blockerId = "blocker_id"
            case blockedId = "blocked_id"
        }
    }

    func isBlocked(_ userId: UUID) -> Bool {
        blockedIds.contains(userId)
    }

    func clear() {
        blockedIds = []
    }

    /// Reload blocked IDs for the signed-in user (or clear when signed out).
    func refresh(for userId: UUID?) async {
        guard let userId else {
            clear()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [BlockRow] = try await supabase.from("user_blocks")
                .select("blocked_id")
                .eq("blocker_id", value: userId)
                .execute()
                .value
            blockedIds = Set(rows.map(\.blockedId))
        } catch {
            // Keep existing cache on transient failures.
            #if DEBUG
            print("[UserBlockService] refresh failed: \(error)")
            #endif
        }
    }

    func block(userId blockedId: UUID, blockerId: UUID) async throws {
        guard blockerId != blockedId else { throw BlockError.cannotBlockSelf }
        do {
            try await supabase.from("user_blocks")
                .upsert(
                    BlockInsert(blockerId: blockerId, blockedId: blockedId),
                    onConflict: "blocker_id,blocked_id"
                )
                .execute()
        } catch {
            throw BlockError.server(error.localizedDescription)
        }
        blockedIds.insert(blockedId)
        Analytics.capture("user_blocked", [
            "blocked_id": blockedId.uuidString.lowercased(),
        ])
        NotificationCenter.default.post(name: .userDidBlock, object: blockedId)
    }

    func unblock(userId blockedId: UUID, blockerId: UUID) async throws {
        do {
            try await supabase.from("user_blocks")
                .delete()
                .eq("blocker_id", value: blockerId)
                .eq("blocked_id", value: blockedId)
                .execute()
        } catch {
            throw BlockError.server(error.localizedDescription)
        }
        blockedIds.remove(blockedId)
        Analytics.capture("user_unblocked", [
            "blocked_id": blockedId.uuidString.lowercased(),
        ])
    }

    /// Hide posts authored by or addressed to blocked users.
    func filterGratitudes(_ items: [Gratitude]) -> [Gratitude] {
        guard !blockedIds.isEmpty else { return items }
        return items.filter { item in
            if blockedIds.contains(item.authorId) { return false }
            if let recipientId = item.recipientId, blockedIds.contains(recipientId) {
                return false
            }
            return true
        }
    }

    func filterProfiles(_ items: [Profile]) -> [Profile] {
        guard !blockedIds.isEmpty else { return items }
        return items.filter { !blockedIds.contains($0.id) }
    }
}
