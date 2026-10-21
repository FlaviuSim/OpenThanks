import Foundation
#if canImport(StoreKit)
import StoreKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Gently asks for an App Store rating after the user's first successful send.
/// We only attempt once — Apple still decides whether to show the system dialog.
enum AppStoreReviewPrompt {
    /// Same key as the accept-time prompt so that ask is not repeated.
    static let requestedKey = "appStoreReviewRequestedAfterReceive.v1"
    private static var scheduled: Task<Void, Never>?

    static var defaults: UserDefaults = .standard
    /// Tests substitute StoreKit. Return false when the dialog cannot be shown.
    @MainActor static var reviewHook: (() -> Bool)?

    enum Event: Equatable {
        case acceptedAppreciation
        case postAcceptMoment
        case successfulSend(count: Int)
    }

    static var hasRequested: Bool {
        defaults.bool(forKey: requestedKey)
    }

    /// Accept never asks. Only the first successful send does, and only once.
    static func shouldRequest(_ event: Event, alreadyRequested: Bool) -> Bool {
        guard !alreadyRequested else { return false }
        if case .successfulSend(let count) = event { return count == 1 }
        return false
    }

    /// Later calls replace a pending delay. Accept events do not schedule.
    @MainActor
    static func schedule(_ event: Event, delaySeconds: Double = 4.5) {
        guard shouldRequest(event, alreadyRequested: hasRequested) else { return }
        scheduled?.cancel()
        scheduled = Task {
            let nanos = UInt64(max(0, delaySeconds) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            await MainActor.run { presentIfNeeded() }
        }
    }

    @MainActor
    static func cancelPending() {
        scheduled?.cancel()
        scheduled = nil
    }

    @MainActor
    private static func presentIfNeeded() {
        guard !hasRequested else { return }
        if let reviewHook {
            guard reviewHook() else { return }
            defaults.set(true, forKey: requestedKey)
            return
        }

        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first
        else { return }

        defaults.set(true, forKey: requestedKey)
        EnjoymentPrompt.recordReceiveSideReviewRequested()
        AppStore.requestReview(in: scene)
        Analytics.capture("app_store_review_requested", ["trigger": "received_appreciation"])
        #endif
    }
}
