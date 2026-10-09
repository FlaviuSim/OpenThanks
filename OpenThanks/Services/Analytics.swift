import Foundation
import PostHog

/// Thin wrapper around PostHog so call sites stay simple and consistent with the web app.
///
/// **App Store / privacy posture**
/// - First-party product analytics only (improve OpenThanks — not ads or cross-app tracking).
/// - `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = false` — no ATT prompt.
/// - `personProfiles = .identifiedOnly` — no anonymous person profiles.
/// - Internal / simulator traffic is excluded (see below).
///
/// Exclusion (no product events):
/// - iOS Simulator (unless DEBUG “Send Analytics” is on)
/// - DEBUG builds (unless that toggle is on)
/// - Known internal emails are tagged `is_internal: true` — filter them out
///   in PostHog insights. We do **not** SDK-`optOut()` founders: that was
///   persisted across launches and blocked later `identify` calls, so iOS
///   installs never got a person profile for those UUIDs.
enum Analytics {
    private static let forceEnableKey = "ot_analytics_force_enable"

    /// Keep in sync with web `lib/analytics-internal.ts`.
    static let internalEmails: Set<String> = [
        "flaviu@simihaian.com",
        "flsimihaian@gmail.com",
    ]

    private static var didSetup = false
    private static let iso8601 = ISO8601DateFormatter()

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
        // First-party funnel metrics — declared in PrivacyInfo.xcprivacy (not tracking).
        config.captureScreenViews = true
        config.captureApplicationLifecycleEvents = true
        config.personProfiles = .identifiedOnly
        PostHogSDK.shared.setup(config)
        // Clear stale founder opt-out from older app builds so identify can run.
        PostHogSDK.shared.optIn()
        didSetup = true
        capture("app_opened", ["platform": "ios"])
        Task { await syncPermissionPersonProperties() }
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
        // Identify must always be allowed — even for founders — or PostHog
        // never creates a person for the UUID / never merges Application Installed.
        PostHogSDK.shared.optIn()

        var props: [String: Any] = ["platform": "ios"]
        if let email, !email.isEmpty { props["email"] = email }
        if let name, !name.isEmpty { props["name"] = name }
        let isInternal = isInternalEmail(email)
        props["is_internal"] = isInternal
        let distinctId = userId.uuidString.lowercased()
        PostHogSDK.shared.identify(distinctId, userProperties: props)
        // Flush promptly so `$identify` lands even if the app is backgrounded.
        PostHogSDK.shared.flush()
        Task { await syncPermissionPersonProperties() }
    }

    static func reset() {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        PostHogSDK.shared.reset()
        PostHogSDK.shared.optIn()
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        capture(
            event,
            properties,
            userProperties: nil,
            userPropertiesSetOnce: nil
        )
    }

    static func capture(
        _ event: String,
        _ properties: [String: Any] = [:],
        userProperties: [String: Any]?,
        userPropertiesSetOnce: [String: Any]?
    ) {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        var props = properties
        props["platform"] = props["platform"] ?? "ios"
        PostHogSDK.shared.capture(
            event,
            properties: props,
            userProperties: userProperties,
            userPropertiesSetOnce: userPropertiesSetOnce
        )
    }

    static func setPersonProperties(
        _ set: [String: Any],
        setOnce: [String: Any] = [:]
    ) {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }
        PostHogSDK.shared.setPersonProperties(
            userPropertiesToSet: set.isEmpty ? nil : set,
            userPropertiesToSetOnce: setOnce.isEmpty ? nil : setOnce
        )
    }

    // MARK: - Push / calendar permission state

    /// Re-reads system notification + calendar linkage and `$set`s person properties.
    /// Safe to call on every launch / foreground — catches flips made in iOS Settings.
    static func syncPermissionPersonProperties() async {
        guard !shouldSkipCapture else { return }
        guard didSetup else { return }

        let status = await NotificationService.authorizationStatus()
        let pushEnabled = NotificationService.isEnabledStatus(status)
        let statusLabel = NotificationService.authorizationStatusLabel(status)

        let appleLinked = CalendarMeetingService.hasFullAccess
        let googleLinked = GoogleCalendarService.isConnected
        let calendarLinked = appleLinked || googleLinked
        let provider = calendarProviderLabel(apple: appleLinked, google: googleLinked)
        let accessLevel = calendarAccessLevelLabel()

        var set: [String: Any] = [
            "push_enabled": pushEnabled,
            "push_authorization_status": statusLabel,
            "calendar_linked": calendarLinked,
        ]
        if let provider {
            set["calendar_provider"] = provider
        } else {
            set["calendar_provider"] = ""
        }
        if let accessLevel {
            set["calendar_access_level"] = accessLevel
        }

        var setOnce: [String: Any] = [:]
        let now = iso8601.string(from: Date())
        if pushEnabled {
            setOnce["first_push_enabled_at"] = now
        }
        if calendarLinked {
            setOnce["first_calendar_linked_at"] = now
        }

        setPersonProperties(set, setOnce: setOnce)
    }

    static func pushPermissionPrompted(source: String, prePrompt: Bool) {
        capture("push_permission_prompted", [
            "source": source,
            "pre_prompt": prePrompt,
        ])
    }

    static func pushPermissionGranted(source: String, authorizationStatus: String) {
        let now = iso8601.string(from: Date())
        capture(
            "push_permission_granted",
            [
                "source": source,
                "authorization_status": authorizationStatus,
            ],
            userProperties: [
                "push_enabled": true,
                "push_authorization_status": authorizationStatus,
            ],
            userPropertiesSetOnce: ["first_push_enabled_at": now]
        )
    }

    static func pushPermissionDenied(source: String) {
        capture(
            "push_permission_denied",
            ["source": source],
            userProperties: [
                "push_enabled": false,
                "push_authorization_status": "denied",
            ],
            userPropertiesSetOnce: nil
        )
    }

    /// APNs registration succeeded — never include the token value.
    static func pushTokenRegistered() {
        capture("push_token_registered")
    }

    static func calendarPermissionPrompted(source: String) {
        capture("calendar_permission_prompted", ["source": source])
    }

    static func calendarConnected(
        provider: String,
        accessLevel: String,
        source: String
    ) {
        let now = iso8601.string(from: Date())
        capture(
            "calendar_connected",
            [
                "provider": provider,
                "access_level": accessLevel,
                "source": source,
            ],
            userProperties: [
                "calendar_linked": true,
                "calendar_provider": provider,
                "calendar_access_level": accessLevel,
            ],
            userPropertiesSetOnce: ["first_calendar_linked_at": now]
        )
        Task { await syncPermissionPersonProperties() }
    }

    static func calendarPermissionDenied(source: String) {
        capture("calendar_permission_denied", ["source": source])
        Task { await syncPermissionPersonProperties() }
    }

    static func calendarDisconnected(provider: String) {
        capture(
            "calendar_disconnected",
            ["provider": provider],
            userProperties: nil,
            userPropertiesSetOnce: nil
        )
        Task { await syncPermissionPersonProperties() }
    }

    private static func calendarProviderLabel(apple: Bool, google: Bool) -> String? {
        switch (apple, google) {
        case (true, true): return "apple_eventkit+google"
        case (true, false): return "apple_eventkit"
        case (false, true): return "google"
        case (false, false): return nil
        }
    }

    private static func calendarAccessLevelLabel() -> String? {
        if CalendarMeetingService.hasFullAccess { return "full" }
        if CalendarMeetingService.accessState == .writeOnly { return "write_only" }
        if GoogleCalendarService.isConnected { return "full" }
        return nil
    }

    /// Successful sign-in (all methods). Includes `platform: ios` automatically.
    static func authSignedIn(method: String, isSignup: Bool = false) {
        var props: [String: Any] = ["method": method]
        if isSignup { props["is_signup"] = true }
        capture("auth_signed_in", props)
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

    /// Join keys shared with the web contract. `senderId` is `gratitudes.author_id`.
    /// `capture` adds `platform: "ios"` when the caller does not set it.
    /// Never put message text, names, or emails in these dictionaries.
    static func appreciationIdentity(gratitudeId: UUID, senderId: UUID) -> [String: Any] {
        [
            "gratitude_id": gratitudeId.uuidString.lowercased(),
            "sender_id": senderId.uuidString.lowercased(),
        ]
    }

    static func appreciationSubmitted(
        gratitudeId: UUID,
        senderId: UUID,
        hasMedia: Bool,
        messageLength: Int,
        hasRecipient: Bool,
        toMember: Bool,
        recipientType: String,
        visibility: String,
        source: String?
    ) {
        var props = appreciationIdentity(gratitudeId: gratitudeId, senderId: senderId)
        props["has_media"] = hasMedia
        props["message_length"] = messageLength
        props["has_recipient"] = hasRecipient
        props["to_member"] = toMember
        props["recipient_type"] = recipientType
        props["visibility"] = visibility
        if let source { props["source"] = source }
        capture("appreciation_submitted", props)
    }

    /// `acceptedAsPrivate` is sent only when true (accept-as-private). A
    /// sender-private note accepted normally keeps `visibility` and omits the flag.
    static func appreciationAccepted(
        gratitudeId: UUID,
        senderId: UUID,
        source: String,
        visibility: String,
        acceptedAsPrivate: Bool = false
    ) {
        var props = appreciationIdentity(gratitudeId: gratitudeId, senderId: senderId)
        props["source"] = source
        props["visibility"] = visibility
        if acceptedAsPrivate {
            props["accepted_as_private"] = true
        }
        capture("appreciation_accepted", props)
    }

    static func appreciationDeclined(
        gratitudeId: UUID,
        senderId: UUID,
        source: String? = nil
    ) {
        var props = appreciationIdentity(gratitudeId: gratitudeId, senderId: senderId)
        if let source { props["source"] = source }
        capture("appreciation_declined", props)
    }

    /// Once per detail or claim screen. Callers guard re-renders; this does not
    /// read the network. `viewerEmail` / the appreciation's recipient email are
    /// compared for `viewer_role` only and are not sent as properties.
    static func appreciationViewed(
        _ gratitude: Gratitude,
        viewerId: UUID?,
        viewerEmail: String?,
        surface: String
    ) {
        var props = appreciationIdentity(
            gratitudeId: gratitude.id,
            senderId: gratitude.authorId
        )
        props["viewer_role"] = appreciationViewerRole(
            viewerId: viewerId,
            senderId: gratitude.authorId,
            recipientId: gratitude.recipientId,
            surface: surface,
            viewerEmail: viewerEmail,
            recipientEmail: gratitude.recipientEmail
        )
        props["surface"] = surface
        props["status"] = appreciationStatusLabel(gratitude.status)
        props["visibility"] = gratitude.visibility == .private ? "private" : "public"
        capture("appreciation_viewed", props)
    }

    /// No session → anonymous. Creator → sender. Recipient id, a detail-page
    /// email match against the address already on the row, or any other
    /// signed-in viewer on the claim screen → recipient. Otherwise other.
    static func appreciationViewerRole(
        viewerId: UUID?,
        senderId: UUID,
        recipientId: UUID?,
        surface: String,
        viewerEmail: String?,
        recipientEmail: String?
    ) -> String {
        guard let viewerId else { return "anonymous" }
        if viewerId == senderId { return "sender" }
        if let recipientId, viewerId == recipientId { return "recipient" }
        if surface == "detail", emailsMatch(viewerEmail, recipientEmail) {
            return "recipient"
        }
        if surface == "claim" { return "recipient" }
        return "other"
    }

    /// Database `rejected` is sent as `declined`. An unset status matches the
    /// pending draft state used elsewhere in the app.
    static func appreciationStatusLabel(_ status: GratitudeStatus?) -> String {
        switch status {
        case .accepted: "accepted"
        case .rejected: "declined"
        case .pending, .none: "pending"
        }
    }

    private static func emailsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalizedEmail(lhs), let rhs = normalizedEmail(rhs) else { return false }
        return lhs == rhs
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        return value
    }

    /// External share actually completed (not merely opened, and not a cancelled sheet).
    static func appreciationShared(
        appreciationId: UUID,
        channel: String,
        voice: String,
        hasCard: Bool,
        hasPhoto: Bool
    ) {
        capture("appreciation_shared", [
            "appreciation_id": appreciationId.uuidString.lowercased(),
            "channel": channel,
            "voice": voice,
            "platform": "ios",
            "has_card": hasCard,
            "has_photo": hasPhoto,
        ])
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
