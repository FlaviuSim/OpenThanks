import UIKit

/// One-time contextual push ask.
///
/// Shows after the first successful send or the first accept, and only while
/// notification permission is still `notDetermined`. Allow is what presents
/// the iOS system prompt. The onboarding notification screen is unchanged.
enum PushPermissionPreprompt {
    enum Trigger: String {
        case send
        case accept
    }

    private static let presentedKey = "pushPreprompt.presented.v1"
    private static let acceptMilestonePassedKey = "pushPreprompt.acceptMilestonePassed.v1"
    private static let gate = NSLock()
    private static var claimed = false

    /// Phone create path. No-ops unless this device's first recorded send just landed.
    static func considerAfterSuccessfulSend() {
        Task { await consider(.send, userId: nil) }
    }

    /// Recipient accept path. No-ops unless this is their first accepted note.
    static func considerAfterSuccessfulAccept(userId: UUID) {
        Task { await consider(.accept, userId: userId) }
    }

    /// Pure eligibility. `acceptedReceivedCount` is nil when the accept lookup failed.
    static func shouldOffer(
        trigger: Trigger,
        alreadyPresented: Bool,
        authorizationNotDetermined: Bool,
        successfulSendCount: Int,
        acceptedReceivedCount: Int?
    ) -> Bool {
        guard authorizationNotDetermined, !alreadyPresented else { return false }
        switch trigger {
        case .send:
            return successfulSendCount == 1
        case .accept:
            return acceptedReceivedCount == 1
        }
    }

    private static func consider(_ trigger: Trigger, userId: UUID?) async {
        if UserDefaults.standard.bool(forKey: presentedKey) { return }
        if await NotificationService.hasResolvedAuthorization() { return }

        switch trigger {
        case .send:
            guard shouldOffer(
                trigger: .send,
                alreadyPresented: false,
                authorizationNotDetermined: true,
                successfulSendCount: EnjoymentPrompt.successfulSendCount,
                acceptedReceivedCount: nil
            ) else { return }
        case .accept:
            if UserDefaults.standard.bool(forKey: acceptMilestonePassedKey) { return }
            guard let userId else { return }
            let acceptedCount: Int
            do {
                acceptedCount = try await GratitudeService.acceptedReceivedCount(recipientId: userId)
            } catch {
                return
            }
            if acceptedCount > 1 {
                UserDefaults.standard.set(true, forKey: acceptMilestonePassedKey)
                return
            }
            guard shouldOffer(
                trigger: .accept,
                alreadyPresented: false,
                authorizationNotDetermined: true,
                successfulSendCount: 0,
                acceptedReceivedCount: acceptedCount
            ) else { return }
        }

        guard tryClaim() else { return }
        await presentWhenStable(trigger)
    }

    private static func tryClaim() -> Bool {
        gate.lock()
        defer { gate.unlock() }
        if claimed || UserDefaults.standard.bool(forKey: presentedKey) { return false }
        claimed = true
        return true
    }

    private static func releaseClaim() {
        gate.lock()
        claimed = false
        gate.unlock()
    }

    /// Waits out the success transition (and a pay-it-forward sheet, if one is
    /// coming up) so the alert sits on top of whatever is already presented.
    @MainActor
    private static func presentWhenStable(_ trigger: Trigger) async {
        try? await Task.sleep(for: .milliseconds(600))
        for _ in 0..<8 {
            if await NotificationService.hasResolvedAuthorization() {
                releaseClaim()
                return
            }
            if presentAlert(trigger) { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
        releaseClaim()
    }

    /// Presents on the current top controller once its transition has finished.
    /// Returns false when another presentation is still moving.
    @MainActor
    private static func presentAlert(_ trigger: Trigger) -> Bool {
        guard let top = stableTopViewController() else { return false }
        let alert = UIAlertController(
            title: "We'll tell you when they see it",
            message: nil,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { _ in
            Analytics.pushPrepromptDismissed(trigger: trigger.rawValue)
        })
        let allow = UIAlertAction(title: "Allow", style: .default) { _ in
            Analytics.pushPrepromptAllowed(trigger: trigger.rawValue)
            Task { @MainActor in
                // Let this alert finish dismissing before the system dialog.
                try? await Task.sleep(for: .milliseconds(350))
                _ = await NotificationService.requestAuthorizationAndRegisterForPushes(
                    analyticsSource: "preprompt"
                )
            }
        }
        alert.addAction(allow)
        alert.preferredAction = allow
        top.present(alert, animated: true)
        UserDefaults.standard.set(true, forKey: presentedKey)
        Analytics.pushPrepromptShown(trigger: trigger.rawValue)
        return true
    }

    @MainActor
    private static func stableTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? scene?.windows.first?.rootViewController
        guard var top = root else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        guard UIApplication.shared.applicationState == .active,
              !(top is UIAlertController),
              top.view.window != nil,
              top.presentedViewController == nil,
              !top.isBeingPresented,
              !top.isBeingDismissed,
              top.transitionCoordinator == nil
        else { return nil }
        return top
    }
}
