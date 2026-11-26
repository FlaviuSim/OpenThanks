import EventKit
import Foundation

/// Chunked historical EventKit upload including `EKEvent.notes`.
/// EventKit enumeration runs off the main actor so Settings “Repair” can’t freeze on it.
enum AppleCalendarHistoryUploader {
    private static let lookbackYears = 10
    private static let chunkDays = 90
    private static let maxEventsPerRequest = 120
    private static let lastUploadKey = "appleCalendarHistoryUploader.lastDoneAt"

    static var lastCompletedAt: Date? {
        let t = UserDefaults.standard.double(forKey: lastUploadKey)
        guard t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    /// Uploads history when the user has server-sync consent and full EventKit access.
    static func uploadIfNeeded(force: Bool = false) async {
        guard CalendarServerSyncConsent.hasConsented else { return }
        guard CalendarMeetingService.hasFullAccess else { return }
        if !force, let last = lastCompletedAt, Date().timeIntervalSince(last) < 20 * 60 * 60 {
            return
        }

        // Keep EventKit + chunking off the main actor — a 10y scan can take minutes.
        // Detached work is cancelled when the caller (troubleshoot timeout) cancels.
        let work = Task.detached(priority: .utility) {
            await Self.uploadHistory()
        }
        await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
    }

    private static func uploadHistory() async {
        let store = EKEventStore()
        let cal = Calendar.current
        let end = Date()
        guard let start = cal.date(byAdding: .year, value: -lookbackYears, to: end) else { return }

        let calendars = store.calendars(for: .event).filter { calendar in
            let title = calendar.title.lowercased()
            if title.contains("holiday") || title.contains("birthday") { return false }
            if calendar.type == .birthday { return false }
            return true
        }

        var cursor = start
        var pending: [CalendarServerAPI.UploadEventPayload] = []
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        func iso(_ date: Date) -> String {
            let fractional = isoFrac.string(from: date)
            return fractional.isEmpty ? isoPlain.string(from: date) : fractional
        }

        func flush(done: Bool) async throws {
            guard !pending.isEmpty || done else { return }
            let batch = pending
            pending = []
            try await CalendarServerAPI.uploadAppleEvents(batch, done: done)
        }

        do {
            while cursor < end {
                try Task.checkCancellation()
                guard let windowEnd = cal.date(byAdding: .day, value: chunkDays, to: cursor) else { break }
                let rangeEnd = min(windowEnd, end)
                let predicate = store.predicateForEvents(
                    withStart: cursor,
                    end: rangeEnd,
                    calendars: calendars
                )
                let events = store.events(matching: predicate)
                for event in events {
                    let attendees: [CalendarServerAPI.AttendeePayload] = (event.attendees ?? []).compactMap { participant in
                        if participant.participantType == .resource { return nil }
                        let email: String? = {
                            let url = participant.url
                            if url.scheme?.lowercased() == "mailto" {
                                let address = url.absoluteString
                                    .replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return address.isEmpty ? nil : address.lowercased()
                            }
                            let raw = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
                            return raw.contains("@") ? raw.lowercased() : nil
                        }()
                        return CalendarServerAPI.AttendeePayload(
                            name: participant.name,
                            email: email,
                            isSelf: participant.isCurrentUser
                        )
                    }
                    let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                    pending.append(
                        CalendarServerAPI.UploadEventPayload(
                            providerEventId: event.eventIdentifier ?? UUID().uuidString,
                            startAt: iso(event.startDate),
                            endAt: iso(event.endDate),
                            title: event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                                ?? "Meeting",
                            notes: (notes?.isEmpty == false) ? notes : nil,
                            isCancelled: event.status == .canceled,
                            isAllDay: event.isAllDay,
                            isRecurring: event.hasRecurrenceRules,
                            attendees: attendees
                        )
                    )
                    if pending.count >= maxEventsPerRequest {
                        try await flush(done: false)
                    }
                }
                cursor = rangeEnd
            }
            try await flush(done: true)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastUploadKey)
            Analytics.calendarServerConnected(provider: "apple")
        } catch is CancellationError {
            // Troubleshoot left the screen / timed out — leave lastCompletedAt unset.
        } catch {
            // Leave lastCompletedAt unset so we retry; surface via connection last_error on server.
            print("[calendar] Apple history upload failed: \(error.localizedDescription)")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
