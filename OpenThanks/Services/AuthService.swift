import AuthenticationServices
import Foundation
import Observation
@_spi(Experimental) import Supabase
import UIKit

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabaseKey,
    options: SupabaseClientOptions(
        auth: .init(
            // Custom scheme — used as ASWebAuthenticationSession callback scheme.
            redirectToURL: AppConfig.redirectURL,
            emitLocalSessionAsInitialSession: true
        )
    )
)

@Observable
final class AuthService {
    enum State { case loading, signedOut, signedIn(UUID) }

    private static let profileCacheKey = "cachedProfile.v1"

    var state: State = .loading
    var currentProfile: Profile? {
        didSet { Self.persistProfile(currentProfile) }
    }
    /// False until the first profile fetch after sign-in finishes.
    /// Prevents flashing the "complete profile" screen for returning users.
    var hasResolvedProfile = false
    var errorMessage: String?
    var devicePushToken: String? {
        didSet {
            guard let devicePushToken, let userId else { return }
            Task { await NotificationService.uploadDeviceToken(devicePushToken, userId: userId) }
        }
    }

    private var authTask: Task<Void, Never>?

    init() {
        // Warm start: show last profile immediately while the session resolves.
        if let cached = Self.loadCachedProfile() {
            currentProfile = cached
        }

        authTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        let cachedMatches = self.currentProfile?.id == session.user.id
                        self.state = .signedIn(session.user.id)
                        if cachedMatches {
                            // Returning user — enter the app on cached profile, refresh in place.
                            self.hasResolvedProfile = true
                        } else if self.currentProfile?.id != session.user.id {
                            self.currentProfile = nil
                            self.hasResolvedProfile = false
                        }
                        if let devicePushToken = self.devicePushToken {
                            Task {
                                await NotificationService.uploadDeviceToken(
                                    devicePushToken,
                                    userId: session.user.id
                                )
                            }
                        }
                        await self.loadOrCreateProfile(
                            userId: session.user.id,
                            email: session.user.email,
                            phone: session.user.phone,
                            metadata: session.user.userMetadata
                        )
                        await MainActor.run {
                            WatchConnectivityService.shared.activate(auth: self)
                            WatchConnectivityService.shared.pushAuthContext()
                        }
                    } else {
                        self.state = .signedOut
                        self.currentProfile = nil
                        self.hasResolvedProfile = false
                        Self.clearCachedProfile()
                        Analytics.reset()
                        await MainActor.run {
                            WatchConnectivityService.shared.pushAuthContext()
                        }
                    }
                case .signedOut, .userDeleted:
                    self.state = .signedOut
                    self.currentProfile = nil
                    self.hasResolvedProfile = false
                    Self.clearCachedProfile()
                    Analytics.reset()
                    await MainActor.run {
                        WatchConnectivityService.shared.pushAuthContext()
                    }
                default:
                    break
                }
            }
        }
    }

    private static func persistProfile(_ profile: Profile?) {
        guard let profile,
              let data = try? JSONEncoder().encode(profile) else {
            return
        }
        UserDefaults.standard.set(data, forKey: profileCacheKey)
    }

    private static func loadCachedProfile() -> Profile? {
        guard let data = UserDefaults.standard.data(forKey: profileCacheKey) else { return nil }
        return try? JSONDecoder().decode(Profile.self, from: data)
    }

    private static func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: profileCacheKey)
    }

    var userId: UUID? {
        if case .signedIn(let id) = state { return id }
        return nil
    }

    // MARK: Profile bootstrap

    private func loadOrCreateProfile(
        userId: UUID,
        email: String?,
        phone: String?,
        metadata: [String: AnyJSON] = [:]
    ) async {
        defer {
            if self.userId == userId {
                hasResolvedProfile = true
            }
        }
        do {
            let existing: [Profile] = try await supabase
                .from("profiles").select().eq("id", value: userId).execute().value
            if let profile = existing.first {
                guard self.userId == userId else { return }
                var resolved = profile
                // Backfill email from auth session (Apple/Google) when the profile row is empty.
                let sessionEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
                let profileEmail = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines)
                if (profileEmail == nil || profileEmail?.isEmpty == true),
                   let sessionEmail, !sessionEmail.isEmpty {
                    let normalized = Self.normalizedEmail(sessionEmail)
                    _ = try? await supabase.from("profiles")
                        .update(["email": normalized])
                        .eq("id", value: userId)
                        .execute()
                    resolved.email = normalized
                }
                currentProfile = resolved
                Analytics.identify(
                    userId: userId,
                    email: resolved.email ?? email,
                    name: resolved.fullName ?? resolved.displayName
                )
                // Phone sync is non-blocking — don't hold the splash on it.
                Task { await self.syncConfirmedPhone(userId: userId) }
                return
            }
            // First sign-in on this backend from mobile: create a minimal row.
            let username = Self.suggestUsername(email: email, phone: phone)
            let row = NewProfileRow(
                id: userId.uuidString,
                email: email,
                phone: phone,
                username: username,
                fullName: Self.metadataString(metadata, keys: ["full_name", "name"]),
                avatarUrl: Self.metadataString(metadata, keys: ["avatar_url", "picture"])
            )
            let inserted: Profile = try await supabase
                .from("profiles")
                .insert(row)
                .select().single().execute().value
            guard self.userId == userId else { return }
            currentProfile = inserted
            Analytics.identify(
                userId: userId,
                email: email,
                name: inserted.fullName ?? inserted.displayName
            )
        } catch {
            errorMessage = "Couldn't load your profile: \(error.localizedDescription)"
        }
    }

    private static func metadataString(_ metadata: [String: AnyJSON], keys: [String]) -> String? {
        for key in keys {
            guard let value = metadata[key] else { continue }
            if case .string(let string) = value {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private struct NewProfileRow: Encodable {
        let id: String
        let email: String?
        let phone: String?
        let username: String
        let fullName: String?
        let avatarUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, email, phone, username
            case fullName = "full_name"
            case avatarUrl = "avatar_url"
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encodeIfPresent(email, forKey: .email)
            try c.encodeIfPresent(phone, forKey: .phone)
            try c.encode(username, forKey: .username)
            try c.encodeIfPresent(fullName, forKey: .fullName)
            try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        }
    }

    private func syncConfirmedPhone(userId: UUID) async {
        guard let session = try? await supabase.auth.session,
              session.user.id == userId,
              let authPhone = Self.confirmedPhone(
                from: session.user.phone,
                confirmedAt: session.user.phoneConfirmedAt
              ),
              currentProfile?.phone != authPhone else { return }
        _ = try? await supabase.from("profiles")
            .update(["phone": authPhone])
            .eq("id", value: userId)
            .execute()
        if var profile = currentProfile, profile.id == userId {
            profile.phone = authPhone
            currentProfile = profile
        }
    }

    private static func suggestUsername(email: String?, phone: String?) -> String {
        let base = email?.split(separator: "@").first.map(String.init)
            ?? phone?.suffix(6).map(String.init).joined()
            ?? "member"
        let clean = base.lowercased().filter { $0.isLetter || $0.isNumber }
        return clean.isEmpty ? "member\(Int.random(in: 1000...9999))"
                             : clean + String(Int.random(in: 100...999))
    }

    // MARK: Sign-in methods

    /// Passkey (WebAuthn) sign-in — Face ID / Touch ID / device unlock.
    /// Requires Passkeys enabled in Supabase (RP ID `openthanks.com`) and
    /// `webcredentials:openthanks.com` Associated Domains.
    @discardableResult
    @MainActor
    func signInWithPasskey(presentationAnchor: ASPresentationAnchor? = nil) async -> Bool {
        errorMessage = nil
        guard #available(iOS 16.0, *) else {
            errorMessage = "Passkeys need iOS 16 or later."
            return false
        }
        do {
            let anchor = presentationAnchor ?? Self.keyPresentationAnchor()
            _ = try await supabase.auth.signInWithPasskey(presentationAnchor: anchor)
            await handleAuthSuccess(method: "passkey")
            return true
        } catch {
            if Self.isPasskeyCancellation(error) { return false }
            errorMessage = Self.passkeyErrorMessage(error)
            return false
        }
    }

    /// Register a passkey for the signed-in user.
    @MainActor
    func registerPasskey(presentationAnchor: ASPresentationAnchor? = nil) async -> Bool {
        errorMessage = nil
        guard #available(iOS 16.0, *) else {
            errorMessage = "Passkeys need iOS 16 or later."
            return false
        }
        do {
            let anchor = presentationAnchor ?? Self.keyPresentationAnchor()
            let passkey = try await supabase.auth.registerPasskey(presentationAnchor: anchor)
            // High-level register API has no friendlyName; label with this device.
            let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !deviceName.isEmpty {
                _ = try? await supabase.auth.renamePasskey(id: passkey.id, friendlyName: deviceName)
            }
            Analytics.capture("passkey_registered", [:])
            return true
        } catch {
            if Self.isPasskeyCancellation(error) { return false }
            errorMessage = Self.passkeyErrorMessage(error)
            return false
        }
    }

    /// List passkeys for the current user.
    /// Does not set ``errorMessage`` — callers show empty state when unavailable.
    func listPasskeys() async -> [PasskeyListItem] {
        do {
            return try await supabase.auth.listPasskeys()
        } catch {
            return []
        }
    }

    /// Delete a registered passkey.
    func deletePasskey(id: String) async -> Bool {
        errorMessage = nil
        do {
            try await supabase.auth.deletePasskey(id: id)
            return true
        } catch {
            errorMessage = Self.passkeyErrorMessage(error)
            return false
        }
    }

    @MainActor
    private static func keyPresentationAnchor() -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        if let key = windows.first(where: \.isKeyWindow) { return key }
        if let any = windows.first { return any }
        return UIWindow()
    }

    private static func isPasskeyCancellation(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return text.contains("cancel") || text.contains("not allowed") || text.contains("abort")
    }

    private static func passkeyErrorMessage(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.localizedCaseInsensitiveContains("disabled")
            || text.localizedCaseInsensitiveContains("passkey_disabled") {
            return "Passkeys aren’t enabled yet. Use email or Apple to sign in, then add a passkey in Settings → Logging In."
        }
        return text
    }

    /// Google OAuth via ASWebAuthenticationSession.
    @discardableResult
    func signInWithGoogle() async -> Bool {
        await signInWithOAuth(provider: .google, method: "google")
    }

    /// LinkedIn OIDC OAuth via ASWebAuthenticationSession (same flow as Google).
    @discardableResult
    func signInWithLinkedIn() async -> Bool {
        await signInWithOAuth(provider: .linkedinOIDC, method: "linkedin")
    }

    /// Shared OAuth path: HTTPS lander (`/auth/mobile`) as Supabase `redirect_to`,
    /// then complete when iOS receives `openthanks://…` (or the HTTPS URL on iOS 17.4+).
    @discardableResult
    private func signInWithOAuth(provider: Provider, method: String) async -> Bool {
        errorMessage = nil
        do {
            _ = try await supabase.auth.signInWithOAuth(
                provider: provider,
                redirectTo: AppConfig.oauthRedirectURL
            ) { @MainActor url in
                try await Self.presentOAuthSession(url: url)
            }
            await handleAuthSuccess(method: method)
            return true
        } catch {
            if Self.isOAuthCancellation(error) { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @MainActor
    private static func presentOAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            // Strong ref kept until the completion handler runs (session holds it weakly).
            var presentation: OAuthPresentationContext? = OAuthPresentationContext()

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.redirectURL.scheme
            ) { callbackURL, error in
                defer { presentation = nil }
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "OpenThanks.OAuth",
                            code: -1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "OAuth returned no callback URL."
                            ]
                        )
                    )
                }
            }

            session.presentationContextProvider = presentation
            session.prefersEphemeralWebBrowserSession = false
            guard session.start() else {
                presentation = nil
                continuation.resume(
                    throwing: NSError(
                        domain: "OpenThanks.OAuth",
                        code: -2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Couldn't start sign-in."
                        ]
                    )
                )
                return
            }
        }
    }

    /// Native Sign in with Apple → Supabase `signInWithIdToken`.
    /// `email` is only present on first Apple authorization; still sync from the session JWT.
    @discardableResult
    func signInWithApple(idToken: String, fullName: String?, email: String? = nil) async -> Bool {
        errorMessage = nil
        do {
            _ = try await supabase.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken
                )
            )
            // Apple only sends the person's name on the first authorization.
            if let fullName, !fullName.isEmpty {
                _ = try? await supabase.auth.update(
                    user: UserAttributes(data: ["full_name": .string(fullName)])
                )
                if var profile = currentProfile,
                   (profile.fullName == nil || profile.fullName?.isEmpty == true) {
                    profile.fullName = fullName
                    currentProfile = profile
                    _ = try? await supabase.from("profiles")
                        .update(["full_name": fullName])
                        .eq("id", value: profile.id)
                        .execute()
                }
            }
            await syncAppleEmailIfNeeded(credentialEmail: email)
            await handleAuthSuccess(method: "apple")
            return true
        } catch {
            errorMessage = Self.friendlyAuthError(error)
            return false
        }
    }

    /// Persists Apple's email (or Hide My Email relay) onto `profiles.email` when missing.
    private func syncAppleEmailIfNeeded(credentialEmail: String?) async {
        guard let session = try? await supabase.auth.session else { return }
        let sessionEmail = session.user.email
        let resolved = [credentialEmail, sessionEmail]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { Self.normalizedEmail($0) }
        guard let resolved else { return }

        let userId = session.user.id
        struct EmailRow: Decodable { let email: String? }
        let rows: [EmailRow] = (try? await supabase.from("profiles")
            .select("email")
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value) ?? []
        let existing = rows.first?.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing, !existing.isEmpty { return }

        _ = try? await supabase.from("profiles")
            .update(["email": resolved])
            .eq("id", value: userId)
            .execute()
        if var profile = currentProfile, profile.id == userId {
            profile.email = resolved
            currentProfile = profile
        }
    }

    private static func friendlyAuthError(_ error: Error) -> String {
        let raw = error.localizedDescription
        let lower = raw.lowercased()
        if lower.contains("unacceptable audience")
            || (lower.contains("audience") && lower.contains("id_token")) {
            return "Apple sign-in isn’t configured for this app yet. In Supabase → Authentication → Providers → Apple, add Client ID “com.openthanks.app” (keep your web Services ID first)."
        }
        return raw
    }

    private static func isOAuthCancellation(_ error: Error) -> Bool {
        if let webAuth = error as? ASWebAuthenticationSessionError,
           webAuth.code == .canceledLogin {
            return true
        }
        let ns = error as NSError
        return ns.domain == ASWebAuthenticationSessionError.errorDomain
            && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}

/// Keeps a presentation anchor alive for `ASWebAuthenticationSession`.
final class OAuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        if let first = scenes.flatMap(\.windows).first {
            return first
        }
        return ASPresentationAnchor()
    }
}

// MARK: - OTP + account

extension AuthService {
    /// App Store / Play Store review account — same as web (`auth-sign-in.tsx`).
    /// Signs in with a fixed password so reviewers never need an inbox OTP.
    static let testAccountEmail = "test@test.com"
    private static let testAccountPassword = "PlayStoreTest2026!"

    static func isTestAccountEmail(_ email: String) -> Bool {
        normalizedEmail(email) == testAccountEmail
    }

    /// Password sign-in for the dedicated review account (no OTP email).
    @discardableResult
    func signInTestAccount() async -> Bool {
        do {
            _ = try await supabase.auth.signIn(
                email: Self.testAccountEmail,
                password: Self.testAccountPassword
            )
            await handleAuthSuccess(method: "email")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func sendEmailCode(to email: String) async -> Bool {
        let email = Self.normalizedEmail(email)
        if Self.isTestAccountEmail(email) {
            return await signInTestAccount()
        }
        do {
            try await supabase.auth.signInWithOTP(email: email, shouldCreateUser: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verifyEmailCode(email: String, code: String) async {
        // New users with "Confirm email" enabled get a signup OTP;
        // returning users get a magic-link/email OTP. Try both.
        let email = Self.normalizedEmail(email)
        var verified = false
        do {
            try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
            verified = true
        } catch {
            do {
                try await supabase.auth.verifyOTP(email: email, token: code, type: .signup)
                verified = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        if verified {
            await handleAuthSuccess(method: "email")
        }
    }

    /// Trim leading/trailing whitespace and lowercase for auth lookups.
    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Normalize to E.164. Accepts `+…` international or 10-digit US/Canada (+1).
    static func normalizedPhone(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let startsWithPlus = trimmed.hasPrefix("+")
        let digits = trimmed.filter(\.isNumber)
        if startsWithPlus {
            return (8...15).contains(digits.count) ? "+\(digits)" : nil
        }
        if digits.count == 10 { return "+1\(digits)" }
        if digits.count == 11, digits.hasPrefix("1") { return "+\(digits)" }
        return nil
    }

    /// Confirmed auth phone only — Supabase may set `user.phone` before OTP verify.
    static func confirmedPhone(from phone: String?, confirmedAt: Date?) -> String? {
        guard let phone, !phone.isEmpty, confirmedAt != nil else { return nil }
        let digits = phone.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return phone.hasPrefix("+") ? phone : "+\(digits)"
    }

    /// Live confirmed phone on the signed-in auth user, if any.
    func currentConfirmedPhone() async -> String? {
        guard let session = try? await supabase.auth.session else { return nil }
        return Self.confirmedPhone(from: session.user.phone, confirmedAt: session.user.phoneConfirmedAt)
    }

    func currentAccountEmail() async -> String? {
        guard let session = try? await supabase.auth.session,
              let email = session.user.email,
              !email.isEmpty else { return nil }
        return email
    }

    func sendPhoneCode(to phone: String) async -> Bool {
        do {
            try await supabase.auth.signInWithOTP(phone: phone)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func verifyPhoneCode(phone: String, code: String) async {
        do {
            try await supabase.auth.verifyOTP(phone: phone, token: code, type: .sms)
            await handleAuthSuccess(method: "phone")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Post-sign-in analytics + one-time signup metadata (`signup_platform`, `signup_method`).
    private func handleAuthSuccess(method: String) async {
        guard let session = try? await supabase.auth.session else { return }
        let isSignup = Self.isFreshSignup(user: session.user)
        if isSignup {
            await persistSignupMetadata(method: method, platform: "ios")
        }
        Analytics.authSignedIn(method: method, isSignup: isSignup)
    }

    /// True when the auth user was created within the last couple of minutes.
    private static func isFreshSignup(user: User) -> Bool {
        Date().timeIntervalSince(user.createdAt) < 120
    }

    /// Record how/where the account was created (once). Stored in user metadata for analytics.
    private func persistSignupMetadata(method: String, platform: String) async {
        guard let session = try? await supabase.auth.session else { return }
        let existing = session.user.userMetadata["signup_platform"]?.stringValue
        guard existing == nil || existing?.isEmpty == true else { return }

        var data = session.user.userMetadata
        data["signup_platform"] = .string(platform)
        data["signup_method"] = .string(method)
        _ = try? await supabase.auth.update(user: UserAttributes(data: data))
    }

    // MARK: Phone on existing account (mirrors web edit profile)

    /// Starts phone add/change — sends SMS OTP. Not saved until `verifyPhoneChange`.
    func sendPhoneChangeCode(to phone: String) async -> Bool {
        errorMessage = nil
        do {
            _ = try await supabase.auth.update(user: UserAttributes(phone: phone))
            return true
        } catch {
            let message = error.localizedDescription
            errorMessage = message.range(of: #"already|registered|exists"#, options: .regularExpression) != nil
                ? "That phone number is already linked to another account."
                : message
            return false
        }
    }

    /// Confirms the SMS OTP from `sendPhoneChangeCode` and syncs `profiles.phone`.
    func verifyPhoneChange(phone: String, code: String) async -> Bool {
        errorMessage = nil
        do {
            try await supabase.auth.verifyOTP(phone: phone, token: code, type: .phoneChange)
            if let userId {
                _ = try? await supabase.from("profiles")
                    .update(["phone": phone])
                    .eq("id", value: userId)
                    .execute()
                if var profile = currentProfile {
                    profile.phone = phone
                    currentProfile = profile
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Removes verified phone via web API (service-role clear). Requires another sign-in method.
    func removePhone() async -> Bool {
        errorMessage = nil
        do {
            guard let session = try? await supabase.auth.session else {
                errorMessage = "Not signed in."
                return false
            }
            if await signInMethodCount(excludingPhone: true) < 1 {
                errorMessage = "Phone is your only sign-in method and cannot be removed. Add an email or Google first."
                return false
            }

            var request = URLRequest(
                url: AppConfig.webAppURL.appending(path: "api/profile/phone")
            )
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Couldn't remove phone number."
                return false
            }
            if !(200..<300).contains(http.statusCode) {
                struct APIError: Decodable { let error: String? }
                errorMessage = (try? JSONDecoder().decode(APIError.self, from: data))?.error
                    ?? "Couldn't remove phone number."
                return false
            }

            _ = try? await supabase.auth.refreshSession()
            if let userId {
                if var profile = currentProfile {
                    profile.phone = nil
                    currentProfile = profile
                }
                // Reload profile row in case the API cleared it.
                let rows: [Profile] = (try? await supabase
                    .from("profiles").select().eq("id", value: userId).execute().value) ?? []
                if let refreshed = rows.first {
                    currentProfile = refreshed
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Linked sign-in methods (identities)

    /// Auth identities linked to the current user (email, Google, Apple, phone, …).
    func fetchLinkedIdentities() async -> [UserIdentity] {
        (try? await supabase.auth.userIdentities()) ?? []
    }

    /// How many distinct ways the user can still sign in after optional exclusions.
    func signInMethodCount(
        excludingIdentityId: UUID? = nil,
        excludingPhone: Bool = false
    ) async -> Int {
        var identities = await fetchLinkedIdentities()
        if let excludingIdentityId {
            identities.removeAll { $0.identityId == excludingIdentityId }
        }
        var providers = Set(identities.map { $0.provider.lowercased() })
        if excludingPhone {
            providers.remove("phone")
        }
        if !excludingPhone, await currentConfirmedPhone() != nil {
            providers.insert("phone")
        }
        if let email = await currentAccountEmail(), !email.isEmpty {
            providers.insert("email")
        }
        return providers.count
    }

    /// Display label for an identity (email preferred).
    static func identityLabel(for identity: UserIdentity) -> String {
        if let email = identity.identityData?["email"]?.stringValue,
           !email.isEmpty {
            return email
        }
        if let phone = identity.identityData?["phone"]?.stringValue,
           !phone.isEmpty {
            return phone
        }
        return identity.provider.capitalized
    }

    /// Link Google to the signed-in account (separate from Calendar OAuth).
    @discardableResult
    func linkGoogleIdentity() async -> Bool {
        errorMessage = nil
        do {
            let response = try await supabase.auth.getLinkIdentityURL(
                provider: .google,
                redirectTo: AppConfig.oauthRedirectURL
            )
            let callback = try await Self.presentOAuthSession(url: response.url)
            _ = try await supabase.auth.session(from: callback)
            return true
        } catch {
            if Self.isOAuthCancellation(error) { return false }
            errorMessage = Self.friendlyIdentityError(error.localizedDescription)
            return false
        }
    }

    /// Unlink a provider identity. Refuses if it would leave zero sign-in methods.
    @discardableResult
    func unlinkIdentity(_ identity: UserIdentity) async -> Bool {
        errorMessage = nil
        if await signInMethodCount(excludingIdentityId: identity.identityId) < 1 {
            errorMessage = "Keep at least one way to sign in."
            return false
        }
        do {
            try await supabase.auth.unlinkIdentity(identity)
            _ = try? await supabase.auth.refreshSession()
            return true
        } catch {
            errorMessage = Self.friendlyIdentityError(error.localizedDescription)
            return false
        }
    }

    /// Clearer copy for common Supabase identity-linking errors.
    private static func friendlyIdentityError(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("manual") && lower.contains("link") {
            return "Manual linking is off for this Supabase project. In Dashboard → Authentication → Providers, turn on “Allow manual linking”, save, then try again."
        }
        if lower.range(of: #"already|registered|exists|identity"#, options: .regularExpression) != nil {
            return "That sign-in method is already linked to another OpenThanks account."
        }
        return message
    }

    /// Start adding/changing account email — Supabase emails a confirmation *link*
    /// (not a 6-digit OTP) to the new address.
    @discardableResult
    func sendEmailChangeConfirmation(to email: String) async -> Bool {
        errorMessage = nil
        let email = Self.normalizedEmail(email)
        guard email.contains("@"), email.contains(".") else {
            errorMessage = "Enter a valid email address."
            return false
        }
        do {
            _ = try await supabase.auth.update(user: UserAttributes(email: email))
            return true
        } catch {
            let message = error.localizedDescription
            errorMessage = message.range(of: #"already|registered|exists"#, options: .regularExpression) != nil
                ? "That email is already linked to another account."
                : message
            return false
        }
    }

    /// After the user opens the change-email confirmation link, refresh auth and sync `profiles.email`.
    /// Returns `true` when the session email matches `expectedEmail`.
    @discardableResult
    func refreshAfterEmailChangeConfirmation(expectedEmail: String) async -> Bool {
        errorMessage = nil
        let expected = Self.normalizedEmail(expectedEmail)
        do {
            _ = try? await supabase.auth.refreshSession()
            let session = try await supabase.auth.session
            let current = session.user.email.map(Self.normalizedEmail)
            guard current == expected else {
                errorMessage = "That email isn’t confirmed yet. Open the link we sent to \(expected), then try again."
                return false
            }
            if let userId {
                _ = try? await supabase.from("profiles")
                    .update(["email": expected])
                    .eq("id", value: userId)
                    .execute()
                if var profile = currentProfile {
                    profile.email = expected
                    currentProfile = profile
                }
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func handleDeepLink(_ url: URL) {
        supabase.auth.handle(url)
    }

    func signOut() async {
        errorMessage = nil
        currentProfile = nil
        hasResolvedProfile = false
        state = .signedOut
        Self.clearCachedProfile()
        WidgetSnapshotRefresher.clear()
        StreakLiveActivityStore.clear()
        Task { await StreakLiveActivityController.clearForSignOut() }
        Analytics.reset()
        try? await supabase.auth.signOut(scope: .local)
    }

    /// Permanently deletes the signed-in account via the web API (same path as
    /// openthanks.com Edit Profile). Required for App Store Guideline 5.1.1(v).
    func deleteAccount() async -> Bool {
        errorMessage = nil
        guard let session = try? await supabase.auth.session else {
            errorMessage = "You’re not signed in."
            return false
        }

        var request = URLRequest(url: AppConfig.webAppURL.appending(path: "api/profile"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                errorMessage = message ?? "Couldn't delete your account. Please try again or email founders@openthanks.com."
                return false
            }
            await GoogleCalendarAuth.disconnect()
            await signOut()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
