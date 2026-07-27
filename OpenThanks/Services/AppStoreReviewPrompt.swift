import StoreKit
import UIKit

/// Gently asks for an App Store rating after the user receives (accepts) an appreciation.
/// We only attempt once — Apple still decides whether to show the system dialog.
enum AppStoreReviewPrompt {
    private static let requestedKey = "appStoreReviewRequestedAfterReceive.v1"
    private static var scheduled: Task<Void, Never>?

    static var hasRequested: Bool {
        UserDefaults.standard.bool(forKey: requestedKey)
    }

    /// Schedule a review prompt. Safe to call multiple times — later calls replace
    /// the pending delay (e.g. accept → wait, then pay-it-forward dismiss → sooner).
    @MainActor
    static func scheduleAfterReceivingAppreciation(delaySeconds: Double = 4.5) {
        guard !hasRequested else { return }
        scheduled?.cancel()
        scheduled = Task {
            let nanos = UInt64(max(0, delaySeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { presentIfNeeded() }
        }
    }

    /// Call when a post-accept sheet (e.g. pay-it-forward) closes so the prompt
    /// isn't competing with another modal.
    @MainActor
    static func scheduleAfterPostAcceptMoment() {
        scheduleAfterReceivingAppreciation(delaySeconds: 0.85)
    }

    @MainActor
    private static func presentIfNeeded() {
        guard !hasRequested else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
        else { return }

        UserDefaults.standard.set(true, forKey: requestedKey)
        AppStore.requestReview(in: scene)
        Analytics.capture("app_store_review_requested", ["trigger": "received_appreciation"])
    }
}
