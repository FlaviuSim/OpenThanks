import Foundation
import PostHog

/// Thin wrapper around PostHog so call sites stay simple and consistent with the web app.
enum Analytics {
    private static var didSetup = false

    static func setup() {
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

    static func identify(userId: UUID, email: String? = nil, name: String? = nil) {
        guard didSetup else { return }
        var props: [String: Any] = ["platform": "ios"]
        if let email, !email.isEmpty { props["email"] = email }
        if let name, !name.isEmpty { props["name"] = name }
        PostHogSDK.shared.identify(userId.uuidString.lowercased(), userProperties: props)
    }

    static func reset() {
        guard didSetup else { return }
        PostHogSDK.shared.reset()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
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
        visibility: String,
        source: String?
    ) {
        var props: [String: Any] = [
            "has_media": hasMedia,
            "message_length": messageLength,
            "has_recipient": hasRecipient,
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
        hasMedia: Bool
    ) {
        var props: [String: Any] = [
            "message_length": messageLength,
            "has_recipient": hasRecipient,
            "has_media": hasMedia,
            "had_started_message": messageLength > 0,
        ]
        if let source { props["source"] = source }
        capture("appreciation_form_abandoned", props)
    }
}
