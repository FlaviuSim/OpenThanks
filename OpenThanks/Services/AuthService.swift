import Foundation
import Supabase
import Observation

let supabase = SupabaseClient(
    supabaseURL: AppConfig.supabaseURL,
    supabaseKey: AppConfig.supabaseKey,
    options: SupabaseClientOptions(
        auth: .init(emitLocalSessionAsInitialSession: true)
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
                        await self.loadOrCreateProfile(userId: session.user.id,
                                                       email: session.user.email,
                                                       phone: session.user.phone)
                    } else {
                        self.state = .signedOut
                        self.currentProfile = nil
                        self.hasResolvedProfile = false
                        Self.clearCachedProfile()
                    }
                case .signedOut, .userDeleted:
                    self.state = .signedOut
                    self.currentProfile = nil
                    self.hasResolvedProfile = false
                    Self.clearCachedProfile()
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

    private func loadOrCreateProfile(userId: UUID, email: String?, phone: String?) async {
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
                currentProfile = profile
                // Phone sync is non-blocking — don't hold the splash on it.
                Task { await self.syncConfirmedPhone(userId: userId) }
                return
            }
            // First sign-in on this backend from mobile: create a minimal row.
            let username = Self.suggestUsername(email: email, phone: phone)
            let inserted: Profile = try await supabase
                .from("profiles")
                .insert(["id": userId.uuidString,
                         "email": email,
                         "phone": phone,
                         "username": username])
                .select().single().execute().value
            guard self.userId == userId else { return }
            currentProfile = inserted
        } catch {
            errorMessage = "Couldn't load your profile: \(error.localizedDescription)"
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

    func sendEmailCode(to email: String) async -> Bool {
        let email = Self.normalizedEmail(email)
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
        do {
            try await supabase.auth.verifyOTP(email: email, token: code, type: .email)
        } catch {
            do {
                try await supabase.auth.verifyOTP(email: email, token: code, type: .signup)
            } catch {
                errorMessage = error.localizedDescription
            }
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
        } catch {
            errorMessage = error.localizedDescription
        }
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

    /// Removes verified phone via web API (service-role clear). Requires an email on the account.
    func removePhone() async -> Bool {
        errorMessage = nil
        do {
            guard let session = try? await supabase.auth.session else {
                errorMessage = "Not signed in."
                return false
            }
            if session.user.email == nil || session.user.email?.isEmpty == true {
                errorMessage = "Phone is your only sign-in method and cannot be removed. Add an email first."
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
        try? await supabase.auth.signOut(scope: .local)
    }
}
