import Foundation

/// Server calendar sync + thank suggestions (openthanks.com).
enum CalendarServerAPI {
    struct ConnectionStatus: Decodable, Sendable {
        let provider: String
        let backfill_status: String
        let last_synced_at: String?
        let last_error: String?
        let server_sync_consent_at: String?
    }

    struct StatusResponse: Decodable, Sendable {
        let connections: [ConnectionStatus]
        let eventCount: Int
        let peopleCount: Int
        let serverSyncEnabled: Bool
    }

    struct Suggestion: Decodable, Sendable, Identifiable {
        let id: UUID
        let person_key: String
        let person_name: String
        let person_email: String?
        let reason: String
        let draft: String?
        let score: Double
        let for_day: String
        let meeting_title: String?
        let source: String?
        let consumed_at: String?
        let created_at: String?
    }

    struct TodayResponse: Decodable, Sendable {
        struct Status: Decodable, Sendable {
            let connected: Bool
            let backfillPending: Bool
            let ready: Bool
            let connections: [ConnectionStatus]
        }

        let suggestion: Suggestion?
        let status: Status
    }

    struct UploadEventPayload: Encodable, Sendable {
        let providerEventId: String
        let startAt: String
        let endAt: String
        let title: String
        let notes: String?
        let isCancelled: Bool
        let isAllDay: Bool
        let isRecurring: Bool
        let attendees: [AttendeePayload]
    }

    struct AttendeePayload: Encodable, Sendable {
        let name: String?
        let email: String?
        let isSelf: Bool
    }

    private static var isoFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static var isoFormatterPlain: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static func isoString(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func authorizedRequest(path: String, method: String) async throws -> URLRequest {
        let session = try await supabase.auth.session
        var request = URLRequest(url: AppConfig.webAppURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    static func connectGoogle(code: String, codeVerifier: String, redirectUri: String) async throws {
        var request = try await authorizedRequest(path: "api/calendar/google/connect", method: "POST")
        let body: [String: String] = [
            "code": code,
            "codeVerifier": codeVerifier,
            "redirectUri": redirectUri,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8)
                ?? "Google Calendar connect failed"
            throw CalendarServerError.api(message)
        }
        struct ConnectResponse: Decodable {
            let accessToken: String?
            let expiresAt: String?
        }
        if let decoded = try? JSONDecoder().decode(ConnectResponse.self, from: data),
           let access = decoded.accessToken {
            GoogleCalendarAuth.persistServerIssuedAccessToken(
                access,
                expiresAt: decoded.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            )
        }
        Analytics.calendarServerConnected(provider: "google")
    }

    static func uploadAppleEvents(_ events: [UploadEventPayload], done: Bool) async throws {
        var request = try await authorizedRequest(path: "api/calendar/apple/upload", method: "POST")
        struct Body: Encodable {
            let events: [UploadEventPayload]
            let done: Bool
            let consent: Bool
        }
        request.httpBody = try JSONEncoder().encode(Body(events: events, done: done, consent: true))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8)
                ?? "Apple calendar upload failed"
            throw CalendarServerError.api(message)
        }
        if done {
            Analytics.calendarBackfillComplete(provider: "apple")
        }
    }

    static func status() async throws -> StatusResponse {
        let request = try await authorizedRequest(path: "api/calendar/status", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CalendarServerError.api("Failed to load calendar status")
        }
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    static func todaySuggestion() async throws -> TodayResponse {
        let request = try await authorizedRequest(path: "api/calendar/suggestions/today", method: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CalendarServerError.api("Failed to load calendar suggestion")
        }
        return try JSONDecoder().decode(TodayResponse.self, from: data)
    }

    static func consumeSuggestion(id: UUID) async {
        guard var request = try? await authorizedRequest(
            path: "api/calendar/suggestions/consume",
            method: "POST"
        ) else { return }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id.uuidString])
        _ = try? await URLSession.shared.data(for: request)
    }

    static func disconnect(provider: String? = nil) async throws {
        var request = try await authorizedRequest(path: "api/calendar/disconnect", method: "POST")
        if let provider {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["provider": provider])
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? "Failed to disconnect calendar"
            throw CalendarServerError.api(message)
        }
    }

    /// Maps a server suggestion into the on-device nudge shape for compose / notifications.
    static func asNudge(_ suggestion: Suggestion, day: Date = Date()) -> GratitudeNudge {
        GratitudeNudge(
            personName: suggestion.person_name,
            email: suggestion.person_email,
            meetingTitle: suggestion.meeting_title ?? "Meeting",
            reason: suggestion.reason,
            eventId: "server:\(suggestion.id.uuidString)",
            day: Calendar.current.startOfDay(for: day),
            score: suggestion.score,
            messageDraft: suggestion.draft
        )
    }
}

enum CalendarServerError: LocalizedError {
    case api(String)

    var errorDescription: String? {
        switch self {
        case .api(let message): return message
        }
    }
}
