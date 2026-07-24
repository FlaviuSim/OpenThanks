import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// One suggested person to thank from today’s calendar.
struct GratitudeNudge: Equatable, Sendable {
    let personName: String
    let email: String?
    let meetingTitle: String
    let reason: String
    let eventId: String
    let day: Date
    let score: Double
    var profile: Profile?
    var messageDraft: String?
}

/// Filters today’s meetings and picks one high-signal gratitude opportunity.
enum GratitudeOpportunityRanker {
    /// Below this score we send no evening notification.
    static let minimumScore: Double = 4.0
    private static let recentThankWindowDays = 14
    private static let maxLargeMeetingAttendees = 8

    private static let noiseTitleTokens: [String] = [
        "focus", "lunch", "block", "busy", "commute", "travel", "ooo",
        "out of office", "holiday", "pto", "vacation", "doctor", "dentist",
        "standup", "stand-up", "stand up", "daily sync", "weekly sync",
        "hold", "placeholder", "heads down", "no meeting",
    ]

    private struct Candidate: Sendable {
        let meeting: CalendarMeeting
        let attendee: CalendarAttendee
        let score: Double
        let reason: String
    }

    /// Picks at most one nudge for `day`. Returns nil on weekends, low confidence, or empty calendars.
    static func pickNudge(
        for day: Date = Date(),
        authorId: UUID?,
        selfEmails: Set<String> = [],
        now: Date = Date()
    ) async -> GratitudeNudge? {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: day)
        // 1 = Sunday, 7 = Saturday
        if weekday == 1 || weekday == 7 { return nil }

        guard CalendarMeetingService.hasFullAccess else { return nil }

        let meetings: [CalendarMeeting]
        do {
            meetings = try CalendarMeetingService.meetings(on: day)
        } catch {
            return nil
        }

        let eightPM = cal.date(
            bySettingHour: 20, minute: 0, second: 0, of: day
        ) ?? day

        // Prefer interactions that will have happened by the 8pm nudge.
        let relevant = meetings.filter { meeting in
            !meeting.isAllDay
                && !meeting.isCancelled
                && meeting.end <= eightPM
                && meeting.start < eightPM
        }

        let recent = await recentlyThankedKeys(authorId: authorId, now: now)
        let normalizedSelf = Set(selfEmails.map { $0.lowercased() })

        var candidates: [Candidate] = []
        for meeting in relevant {
            guard passesNoiseFilter(meeting) else { continue }
            let others = meeting.otherAttendees.filter { attendee in
                if let email = attendee.email?.lowercased(), normalizedSelf.contains(email) {
                    return false
                }
                return true
            }
            guard !others.isEmpty else { continue }
            guard others.count <= maxLargeMeetingAttendees || others.count == 1 else { continue }

            for attendee in others {
                if isRecentlyThanked(attendee, keys: recent) { continue }
                let scored = score(meeting: meeting, attendee: attendee, otherCount: others.count)
                guard scored.score >= minimumScore else { continue }
                candidates.append(
                    Candidate(
                        meeting: meeting,
                        attendee: attendee,
                        score: scored.score,
                        reason: scored.reason
                    )
                )
            }
        }

        guard !candidates.isEmpty else { return nil }

        // Highest heuristic score first; AI may re-pick among the top set.
        let sorted = candidates.sorted { $0.score > $1.score }
        let top = Array(sorted.prefix(8))
        let chosen = await selectWithAI(from: top) ?? top[0]

        var nudge = GratitudeNudge(
            personName: chosen.attendee.displayName,
            email: chosen.attendee.email,
            meetingTitle: chosen.meeting.title,
            reason: chosen.reason,
            eventId: chosen.meeting.id,
            day: cal.startOfDay(for: day),
            score: chosen.score,
            profile: nil,
            messageDraft: nil
        )

        if let email = nudge.email {
            nudge.profile = try? await GratitudeService.profile(email: email)
        }
        nudge.messageDraft = await makeDraft(for: nudge)
        return nudge
    }

    // MARK: Filters & scoring

    private static func passesNoiseFilter(_ meeting: CalendarMeeting) -> Bool {
        let title = meeting.title.lowercased()
        if noiseTitleTokens.contains(where: { title.contains($0.lowercased()) }) {
            // Soft exception: 1:1 named meetings that also say "sync" can still pass via score,
            // but hard-drop clear noise tokens like focus/lunch/ooo.
            let hard = ["focus", "lunch", "block", "busy", "commute", "travel",
                        "ooo", "out of office", "holiday", "pto", "vacation",
                        "hold", "placeholder", "heads down", "no meeting"]
            if hard.contains(where: { title.contains($0) }) { return false }
        }
        return true
    }

    private static func score(
        meeting: CalendarMeeting,
        attendee: CalendarAttendee,
        otherCount: Int
    ) -> (score: Double, reason: String) {
        var score = 0.0
        var reasons: [String] = []

        if otherCount == 1 {
            score += 5
            reasons.append("one-on-one")
        } else if otherCount <= 4 {
            score += 3
            reasons.append("small meeting")
        } else {
            score += 1
        }

        if attendee.email != nil {
            score += 1.5
        }

        let minutes = meeting.durationMinutes
        if minutes >= 25 && minutes <= 90 {
            score += 2
            reasons.append("substantive conversation")
        } else if minutes >= 15 {
            score += 1
        } else {
            score -= 1
        }

        let title = meeting.title.lowercased()
        if title.contains("standup") || title.contains("stand-up") || title.contains("daily") {
            score -= 2.5
        }
        if meeting.isRecurring && otherCount > 2 {
            score -= 1.5
        }
        if title.contains("1:1") || title.contains("1-1") || title.contains("one on one") {
            score += 2
            reasons.append("dedicated 1:1")
        }
        if title.contains("intro") || title.contains("coffee") || title.contains("catch up") {
            score += 1.5
            reasons.append("personal connection")
        }

        let reason = reasons.isEmpty
            ? "you met about \(meeting.title)"
            : reasons.joined(separator: ", ")
        return (score, reason)
    }

    // MARK: Recent thanks

    private static func recentlyThankedKeys(authorId: UUID?, now: Date) async -> Set<String> {
        guard let authorId else { return [] }
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -recentThankWindowDays, to: now) else {
            return []
        }
        let sent = (try? await GratitudeService.sentBy(userId: authorId, viewerId: authorId, limit: 80)) ?? []
        var keys = Set<String>()
        for g in sent {
            let when = g.createdAt ?? g.acceptedAt ?? .distantPast
            guard when >= cutoff else { continue }
            if let id = g.recipientId {
                keys.insert("id:\(id.uuidString.lowercased())")
            }
            if let email = g.recipientEmail?.lowercased(), !email.isEmpty {
                keys.insert("email:\(email)")
            }
            if let name = g.recipientName?.lowercased(), !name.isEmpty {
                keys.insert("name:\(name)")
            }
            if let name = g.recipient?.fullName?.lowercased(), !name.isEmpty {
                keys.insert("name:\(name)")
            }
        }
        return keys
    }

    private static func isRecentlyThanked(_ attendee: CalendarAttendee, keys: Set<String>) -> Bool {
        if let email = attendee.email?.lowercased(), keys.contains("email:\(email)") {
            return true
        }
        if let name = attendee.name?.lowercased(), keys.contains("name:\(name)") {
            return true
        }
        return false
    }

    // MARK: AI selection & draft

    private static func selectWithAI(from candidates: [Candidate]) async -> Candidate? {
        guard candidates.count > 1, AppreciationAI.isAvailable else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let lines = candidates.enumerated().map { index, c in
                let email = c.attendee.email ?? "no-email"
                return "\(index). \(c.attendee.displayName) <\(email)> — \(c.meeting.title) (score \(String(format: "%.1f", c.score)))"
            }.joined(separator: "\n")

            let prompt = """
            Pick the single best person to thank today after these meetings.
            Prefer genuine 1:1 or small meaningful conversations over large recurring standups.
            Reply with ONLY the index number (0-\(candidates.count - 1)).

            \(lines)
            """
            do {
                let session = LanguageModelSession(
                    instructions: """
                    You help OpenThanks choose one gratitude opportunity from a calendar day.
                    Reply with a single integer index only — no words, no punctuation.
                    """
                )
                let response = try await session.respond(to: prompt)
                let raw = String(response.content)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let value = Int(raw.filter(\.isNumber).prefix(2)),
                   candidates.indices.contains(value) {
                    return candidates[value]
                }
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    private static func makeDraft(for nudge: GratitudeNudge) async -> String {
        let title = nudge.meetingTitle
        let base: String
        if title.count <= 48, !title.lowercased().hasPrefix("meeting") {
            base = "Thank you for \(title) today — I appreciated our conversation."
        } else {
            base = "Thank you for our conversation earlier today. I appreciated your time and perspective."
        }

        guard AppreciationAI.isAvailable else { return base }
        return (try? await AppreciationAI.rewrite(base, style: .warmer)) ?? base
    }
}
