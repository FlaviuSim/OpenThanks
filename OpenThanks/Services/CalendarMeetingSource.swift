import Foundation

/// A calendar provider that can supply today’s meetings for gratitude ranking.
protocol CalendarMeetingSource: Sendable {
    var id: String { get }
    var isConnected: Bool { get }
    func meetings(on day: Date) async throws -> [CalendarMeeting]
}

/// Merges Apple Calendar (EventKit) and Google Calendar into one meeting list.
enum CalendarMeetingAggregator {
    /// True when at least one source can supply meetings.
    static var hasAnyConnectedSource: Bool {
        CalendarMeetingService.hasFullAccess || GoogleCalendarService.isConnected
    }

    static func connectedSourceSummary() -> String {
        var parts: [String] = []
        if CalendarMeetingService.hasFullAccess { parts.append("Apple") }
        if GoogleCalendarService.isConnected { parts.append("Google") }
        switch parts.count {
        case 0: return "None"
        case 1: return parts[0]
        default: return parts.joined(separator: " + ")
        }
    }

    /// Union of connected sources, de-duped by start + title + attendee emails.
    static func meetings(on day: Date = Date()) async -> [CalendarMeeting] {
        var combined: [CalendarMeeting] = []

        if CalendarMeetingService.hasFullAccess {
            if let apple = try? CalendarMeetingService.meetings(on: day) {
                combined.append(contentsOf: apple)
            }
        }

        if GoogleCalendarService.isConnected {
            if let google = try? await GoogleCalendarService.meetings(on: day) {
                combined.append(contentsOf: google)
            }
        }

        return dedupe(combined).sorted { $0.start < $1.start }
    }

    private static func dedupe(_ meetings: [CalendarMeeting]) -> [CalendarMeeting] {
        var seen = Set<String>()
        var result: [CalendarMeeting] = []
        for meeting in meetings {
            let emails = meeting.otherAttendees
                .compactMap(\.email)
                .map { $0.lowercased() }
                .sorted()
                .joined(separator: ",")
            let startKey = ISO8601DateFormatter().string(from: meeting.start)
            let key = "\(startKey)|\(meeting.title.lowercased())|\(emails)"
            if seen.insert(key).inserted {
                result.append(meeting)
            }
        }
        return result
    }
}
