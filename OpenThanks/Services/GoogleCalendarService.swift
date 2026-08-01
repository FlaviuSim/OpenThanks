import Foundation

/// Fetches today’s events from Google Calendar API into `CalendarMeeting`.
enum GoogleCalendarService {
    static let sourceId = "google"

    static var isConnected: Bool {
        GoogleCalendarAuth.isConnected
    }

    /// Primary calendar events for the local day window.
    static func meetings(on day: Date = Date()) async throws -> [CalendarMeeting] {
        guard isConnected else { return [] }

        let token = try await GoogleCalendarAuth.validAccessToken()
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(
            string: "https://www.googleapis.com/calendar/v3/calendars/primary/events"
        )!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100"),
        ]
        guard let url = components.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GoogleCalendarError.apiFailed("No response from Google Calendar")
        }
        if http.statusCode == 401 {
            throw GoogleCalendarError.notConnected
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleCalendarError.apiFailed("Google Calendar error (\(http.statusCode)). \(body)")
        }

        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (decoded.items ?? []).map { event in
            let isAllDay = event.start.date != nil
            let startDate = event.start.resolvedDate ?? start
            let endDate = event.end.resolvedDate ?? startDate.addingTimeInterval(3600)
            let attendees: [CalendarAttendee] = (event.attendees ?? []).compactMap { attendee in
                if attendee.resource == true { return nil }
                return CalendarAttendee(
                    name: attendee.displayName,
                    email: attendee.email?.lowercased(),
                    isCurrentUser: attendee.selfAttendee == true
                )
            }
            return CalendarMeeting(
                id: "google:\(event.id)",
                title: event.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "Meeting",
                start: startDate,
                end: endDate,
                isAllDay: isAllDay,
                isCancelled: (event.status ?? "").lowercased() == "cancelled",
                isRecurring: event.recurringEventId != nil,
                attendees: attendees
            )
        }
        .sorted { $0.start < $1.start }
    }

    // MARK: - API models

    private struct EventsResponse: Decodable {
        let items: [EventItem]?
    }

    private struct EventItem: Decodable {
        let id: String
        let summary: String?
        let status: String?
        let recurringEventId: String?
        let start: EventDate
        let end: EventDate
        let attendees: [APIAttendee]?
    }

    private struct EventDate: Decodable {
        let date: String?
        let dateTime: String?

        var resolvedDate: Date? {
            if let dateTime {
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = withFrac.date(from: dateTime) { return d }
                let plain = ISO8601DateFormatter()
                plain.formatOptions = [.withInternetDateTime]
                return plain.date(from: dateTime)
            }
            if let date {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.date(from: date)
            }
            return nil
        }
    }

    private struct APIAttendee: Decodable {
        let email: String?
        let displayName: String?
        let resource: Bool?
        let selfAttendee: Bool?

        enum CodingKeys: String, CodingKey {
            case email, displayName, resource
            case selfAttendee = "self"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
