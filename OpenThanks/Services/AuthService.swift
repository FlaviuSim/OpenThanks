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

    var state: State = .loading
    var currentProfile: Profile?
    var errorMessage: String?
    var devicePushToken: String? {
        didSet {
            guard let devicePushToken, let userId else { return }
            Task { await NotificationService.uploadDeviceToken(devicePushToken, userId: userId) }
        }
    }

    private var authTask: Task<Void, Never>?

    init() {
        authTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        self.state = .signedIn(session.user.id)
                        if let devicePushToken = self.devicePushToken {
                            await NotificationService.uploadDeviceToken(
                                devicePushToken,
                                userId: session.user.id
                            )
                        }
                        await self.loadOrCreateProfile(userId: session.user.id,
                                                       email: session.user.email,
                                                       phone: session.user.phone)
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut, .userDeleted:
                    self.state = .signedOut
                    self.currentProfile = nil
                default:
                    break
                }
            }
        }
    }

    var userId: UUID? {
        if case .signedIn(let id) = state { return id }
        return nil
    }

    // MARK: Profile bootstrap

    private func loadOrCreateProfile(userId: UUID, email: String?, phone: String?) async {
        do {
            let existing: [Profile] = try await supabase
                .from("profiles").select().eq("id", value: userId).execute().value
            if let profile = existing.first {
                guard self.userId == userId else { return }
                currentProfile = profile
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

    func handleDeepLink(_ url: URL) {
        supabase.auth.handle(url)
    }

    func signOut() async {
        errorMessage = nil
        currentProfile = nil
        state = .signedOut
        try? await supabase.auth.signOut(scope: .local)
    }
}
