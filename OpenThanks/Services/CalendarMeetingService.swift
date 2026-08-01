import EventKit
import Foundation

/// Attendee on a calendar event (name/email when EventKit provides them).
struct CalendarAttendee: Hashable, Sendable {
    let name: String?
    let email: String?
    let isCurrentUser: Bool

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let email, !email.isEmpty { return email }
        return "Someone"
    }
}

/// Lightweight meeting snapshot for on-device gratitude ranking (no notes/attachments).
struct CalendarMeeting: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isCancelled: Bool
    let isRecurring: Bool
    let attendees: [CalendarAttendee]

    var durationMinutes: Int {
        max(1, Int(end.timeIntervalSince(start) / 60))
    }

    var otherAttendees: [CalendarAttendee] {
        attendees.filter { !$0.isCurrentUser }
    }
}

/// Apple Calendar via EventKit. All processing stays on-device.
enum CalendarMeetingService {
    static let sourceId = "apple"
    private static let store = EKEventStore()

    enum AccessState: Equatable {
        case notDetermined
        case denied
        case restricted
        case fullAccess
        case writeOnly
    }

    static var accessState: AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    static var hasFullAccess: Bool {
        accessState == .fullAccess
    }

    /// Requests full calendar access so we can read attendees.
    @discardableResult
    static func requestAccess() async -> Bool {
        if hasFullAccess { return true }
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted
        } catch {
            return false
        }
    }

    /// Events on the local calendar day for `day`, excluding holiday calendars when possible.
    static func meetings(on day: Date = Date()) throws -> [CalendarMeeting] {
        guard hasFullAccess else { return [] }

        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }

        let calendars = store.calendars(for: .event).filter { calendar in
            // Skip obvious holiday / birthday calendars.
            let title = calendar.title.lowercased()
            if title.contains("holiday") || title.contains("birthday") { return false }
            if calendar.type == .birthday || calendar.type == .subscription {
                // Keep subscriptions that look like work calendars; drop birthdays.
                if calendar.type == .birthday { return false }
            }
            return true
        }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate)

        return events.map { event in
            let attendees: [CalendarAttendee] = (event.attendees ?? []).compactMap { participant in
                // Skip resources / rooms when labeled as such.
                if participant.participantType == .resource { return nil }
                let email = email(from: participant.url)
                let name = participant.name
                return CalendarAttendee(
                    name: name,
                    email: email,
                    isCurrentUser: participant.isCurrentUser
                )
            }

            return CalendarMeeting(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "Meeting",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                isCancelled: event.status == .canceled,
                isRecurring: event.hasRecurrenceRules,
                attendees: attendees
            )
        }
        .sorted { $0.start < $1.start }
    }

    private static func email(from url: URL?) -> String? {
        guard let url else { return nil }
        // EventKit often uses mailto: addresses.
        if url.scheme?.lowercased() == "mailto" {
            let address = url.absoluteString
                .replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return address.isEmpty ? nil : address.lowercased()
        }
        let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.contains("@") { return raw.lowercased() }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
