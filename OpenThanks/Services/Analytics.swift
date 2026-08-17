import Foundation
import PostHog

/// Thin wrapper around PostHog so call sites stay simple and consistent with the web app.
///
/// Exclusion (no product events):
/// - iOS Simulator (unless DEBUG “Send Analytics” is on)
/// - DEBUG builds (unless that toggle is on)
/// - Known internal emails → SDK opt-out after identify
enum Analytics {
    private static let forceEnableKey = "ot_analytics_force_enable"

    /// Keep in sync with web `lib/analytics-internal.ts`.
    static let internalEmails: Set<String> = [
        "flaviu@simihaian.com",
        "flsimihaian@gmail.com",
    ]

    private static var didSetup = false

    private static var forceEnabled: Bool {
        UserDefaults.standard.bool(forKey: forceEnableKey)
    }

    /// Simulator and DEBUG never capture unless the Settings toggle is on.
    private static var shouldSkipCapture: Bool {
        #if targetEnvironment(simulator)
        return !forceEnabled
        #elseif DEBUG
        return !forceEnabled
        #else
        return false
        #endif
    }

    static func isInternalEmail(_ email: String?) -> Bool {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !email.isEmpty else { return false }
        return internalEmails.contains(email)
    }

    static func setup() {
        guard !shouldSkipCapture else { return }
        guard !didSetup else { return }
        guard !AppConfig.postHogKey.isEmpty else { return }

        let config = PostHogConfig(
            projectToken: AppConfig.postHogKey,
            host: AppConfig.postHogHost
        )
        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)
        didSetup = true
        capture("app_opened", ["platform": "ios"])
    }

    /// DEBUG Settings: allow sending from Simulator / Debug builds.
    static func setForceEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: forceEnableKey)
        if enabled {
            setup()
            PostHogSDK.shared.optIn()
        } else if didSetup {
            PostHogSDK.shared.optOut()
        }
    }

    static func identify(userId: UUID, email: String? = nil, name: String? = nil) {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        var props: [String: Any] = ["platform": "ios"]
        if let email, !email.isEmpty { props["email"] = email }
        if let name, !name.isEmpty { props["name"] = name }
        let isInternal = isInternalEmail(email)
        props["is_internal"] = isInternal
        PostHogSDK.shared.identify(userId.uuidString.lowercased(), userProperties: props)

        // Founder / test accounts: stop capturing so device testing
        // on Release builds doesn't pollute product metrics.
        if isInternal {
            PostHogSDK.shared.optOut()
        } else {
            PostHogSDK.shared.optIn()
        }
    }

    static func reset() {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        PostHogSDK.shared.reset()
        PostHogSDK.shared.optIn()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        var props = properties
        props["platform"] = props["platform"] ?? "ios"
        PostHogSDK.shared.capture(event, properties: props)
    }

    // MARK: - Compose funnel (aligned with web PostHog events)

    static func appreciationFormStarted(source: String) {
        capture("appreciation_form_started", ["source": source])
    }

    static func appreciationAIRewrite(tone: String = "warmer") {
        capture("appreciation_ai_rewrite", ["tone": tone])
    }

    static func appreciationVoiceDictation(messageLength: Int) {
        capture("appreciation_voice_dictation", ["message_length": messageLength])
    }

    static func appreciationSubmitted(
        hasMedia: Bool,
        messageLength: Int,
        hasRecipient: Bool,
        toMember: Bool,
        recipientType: String,
        visibility: String,
        source: String?
    ) {
        var props: [String: Any] = [
            "has_media": hasMedia,
            "message_length": messageLength,
            "has_recipient": hasRecipient,
            "to_member": toMember,
            "recipient_type": recipientType,
            "visibility": visibility,
        ]
        if let source { props["source"] = source }
        capture("appreciation_submitted", props)
    }

    static func appreciationFailed(error: String, source: String?) {
        var props: [String: Any] = ["error": String(error.prefix(200))]
        if let source { props["source"] = source }
        capture("appreciation_failed", props)
    }

    /// Fired when compose is dismissed without a successful send — key drop-off signal.
    static func appreciationFormAbandoned(
        source: String?,
        messageLength: Int,
        hasRecipient: Bool,
        toMember: Bool,
        recipientType: String,
        hasMedia: Bool
    ) {
        var props: [String: Any] = [
            "message_length": messageLength,
            "has_recipient": hasRecipient,
            "to_member": toMember,
            "recipient_type": recipientType,
            "has_media": hasMedia,
            "had_started_message": messageLength > 0,
        ]
        if let source { props["source"] = source }
        capture("appreciation_form_abandoned", props)
    }
}
