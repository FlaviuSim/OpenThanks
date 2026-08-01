import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Separate Google OAuth for Calendar readonly access (not Supabase sign-in).
enum GoogleCalendarAuth {
    private static let accessTokenKey = "accessToken"
    private static let refreshTokenKey = "refreshToken"
    private static let expiryKey = "expiry"

    static var isConnected: Bool {
        KeychainStore.string(forKey: refreshTokenKey) != nil
            || KeychainStore.string(forKey: accessTokenKey) != nil
    }

    static var hasClientConfigured: Bool {
        !AppConfig.googleCalendarClientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
            && !AppConfig.googleCalendarClientID.contains("YOUR_GOOGLE")
    }

    /// Opens Google consent; stores tokens in Keychain on success.
    @MainActor
    static func connect() async throws {
        guard hasClientConfigured else {
            throw GoogleCalendarError.clientNotConfigured
        }

        let verifier = randomURLSafeString(64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = randomURLSafeString(24)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleCalendarClientID),
            URLQueryItem(name: "redirect_uri", value: AppConfig.googleCalendarRedirectURL.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = components.url else {
            throw GoogleCalendarError.invalidAuthURL
        }

        let callback = try await presentOAuthSession(url: authURL)
        guard let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            throw GoogleCalendarError.missingCode
        }
        if let err = items.first(where: { $0.name == "error" })?.value {
            throw GoogleCalendarError.oauthError(err)
        }
        guard let returnedState = items.first(where: { $0.name == "state" })?.value,
              returnedState == state,
              let code = items.first(where: { $0.name == "code" })?.value
        else {
            throw GoogleCalendarError.missingCode
        }

        try await exchangeCode(code, verifier: verifier)
    }

    static func isUserCancellation(_ error: Error) -> Bool {
        if let webAuth = error as? ASWebAuthenticationSessionError,
           webAuth.code == .canceledLogin {
            return true
        }
        let ns = error as NSError
        return ns.domain == ASWebAuthenticationSessionError.errorDomain
            && ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }

    static func disconnect() async {
        if let token = KeychainStore.string(forKey: accessTokenKey)
            ?? KeychainStore.string(forKey: refreshTokenKey) {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(token.urlQueryEscaped)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.removeAll(keys: [accessTokenKey, refreshTokenKey, expiryKey])
    }

    /// Valid access token, refreshing if needed.
    static func validAccessToken() async throws -> String {
        if let token = KeychainStore.string(forKey: accessTokenKey),
           let expiryRaw = KeychainStore.string(forKey: expiryKey),
           let expiry = TimeInterval(expiryRaw),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        guard let refresh = KeychainStore.string(forKey: refreshTokenKey) else {
            throw GoogleCalendarError.notConnected
        }
        try await refreshAccessToken(refresh)
        guard let token = KeychainStore.string(forKey: accessTokenKey) else {
            throw GoogleCalendarError.notConnected
        }
        return token
    }

    // MARK: - Token exchange

    private static func exchangeCode(_ code: String, verifier: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": AppConfig.googleCalendarClientID,
            "redirect_uri": AppConfig.googleCalendarRedirectURL.absoluteString,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        request.httpBody = formEncode(body).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try persistTokens(data: data, response: response, allowMissingRefresh: false)
    }

    private static func refreshAccessToken(_ refresh: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "refresh_token": refresh,
            "client_id": AppConfig.googleCalendarClientID,
            "grant_type": "refresh_token",
        ]
        request.httpBody = formEncode(body).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try persistTokens(data: data, response: response, allowMissingRefresh: true)
    }

    private static func persistTokens(
        data: Data,
        response: URLResponse,
        allowMissingRefresh: Bool
    ) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Token exchange failed"
            throw GoogleCalendarError.tokenExchangeFailed(message)
        }
        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Int?
            let refresh_token: String?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        KeychainStore.set(decoded.access_token, forKey: accessTokenKey)
        let expiresIn = decoded.expires_in ?? 3600
        KeychainStore.set(
            String(Date().timeIntervalSince1970 + Double(expiresIn)),
            forKey: expiryKey
        )
        if let refresh = decoded.refresh_token {
            KeychainStore.set(refresh, forKey: refreshTokenKey)
        } else if !allowMissingRefresh, KeychainStore.string(forKey: refreshTokenKey) == nil {
            throw GoogleCalendarError.tokenExchangeFailed("Missing refresh token")
        }
    }

    // MARK: - OAuth session

    @MainActor
    private static func presentOAuthSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var presentation: OAuthPresentationContext? = OAuthPresentationContext()
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AppConfig.googleCalendarURLScheme
            ) { callbackURL, error in
                defer { presentation = nil }
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: GoogleCalendarError.missingCode)
                }
            }
            session.presentationContextProvider = presentation
            session.prefersEphemeralWebBrowserSession = false
            guard session.start() else {
                presentation = nil
                continuation.resume(throwing: GoogleCalendarError.sessionStartFailed)
                return
            }
        }
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields
            .map { "\($0.key)=\($0.value.urlQueryEscaped)" }
            .joined(separator: "&")
    }
}

enum GoogleCalendarError: LocalizedError {
    case clientNotConfigured
    case invalidAuthURL
    case missingCode
    case oauthError(String)
    case notConnected
    case tokenExchangeFailed(String)
    case sessionStartFailed
    case apiFailed(String)

    var errorDescription: String? {
        switch self {
        case .clientNotConfigured:
            return "Google Calendar isn’t configured yet. Add a Google OAuth client ID in AppConfig."
        case .invalidAuthURL:
            return "Couldn't start Google Calendar sign-in."
        case .missingCode:
            return "Google Calendar sign-in didn’t return an authorization code."
        case .oauthError(let message):
            return "Google Calendar: \(message)"
        case .notConnected:
            return "Google Calendar isn’t connected."
        case .tokenExchangeFailed(let message):
            return "Couldn't finish Google Calendar sign-in. \(message)"
        case .sessionStartFailed:
            return "Couldn't open Google Calendar sign-in."
        case .apiFailed(let message):
            return message
        }
    }
}

private extension String {
    var urlQueryEscaped: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26")
            .replacingOccurrences(of: "+", with: "%2B")
            ?? self
    }
}
