import Foundation

/// Gratitude Friday prompts — keep in sync with
/// `v0-gratitude-network/lib/friday-prompts.ts` (same week-index formula).
enum FridayPrompts {
    struct Prompt: Equatable {
        let subject: String
        let headline: String
        let body: String
        let preheader: String
        /// Placeholder / starter line shown in compose when opening from this prompt.
        let starterIdea: String
    }

    private static let questions: [(headline: String, starter: String)] = [
        (
            "Who made your week just a little bit better, even if they don't realize it?",
            "Thank you for making my week a little better when…"
        ),
        (
            "Who helped you solve a problem this week?",
            "Thank you for helping me solve … this week."
        ),
        (
            "Who made you smile or laugh when you needed it most?",
            "Thank you for making me smile when…"
        ),
        (
            "Who quietly supports you behind the scenes every week?",
            "Thank you for quietly supporting me — especially when…"
        ),
        (
            "Who inspired you through their actions this week?",
            "Thank you for inspiring me by…"
        ),
        (
            "Who gave you an opportunity that changed your path—even years ago?",
            "Thank you for the opportunity you gave me to…"
        ),
        (
            "Who believed in you before you fully believed in yourself?",
            "Thank you for believing in me when…"
        ),
        (
            "Who deserves a thank you you've never actually said out loud?",
            "Thank you for … — I've never said this out loud before."
        ),
        (
            "Who taught you a lesson you're still using today?",
            "Thank you for teaching me … — I still use it today."
        ),
        (
            "Who made a sacrifice that benefited you?",
            "Thank you for the sacrifice you made when…"
        ),
        (
            "Who checked in on you recently without wanting anything in return?",
            "Thank you for checking in on me when…"
        ),
        (
            "Who has been consistently there for you, even in small ways?",
            "Thank you for being consistently there for me, especially…"
        ),
        (
            "Who do you appreciate today more than you did a year ago?",
            "Thank you for … — I appreciate you more than I did a year ago."
        ),
        (
            "Who made your work easier this week?",
            "Thank you for making my work easier this week by…"
        ),
        (
            "Who have you been meaning to thank for a long time?",
            "Thank you for … — I've been meaning to say this for a long time."
        ),
        (
            "Who gave you confidence when you needed encouragement?",
            "Thank you for giving me confidence when…"
        ),
        (
            "Who helped shape the person you've become?",
            "Thank you for helping shape who I've become through…"
        ),
        (
            "Who made an ordinary moment feel special this week?",
            "Thank you for making … feel special this week."
        ),
        (
            "Who rarely gets recognized but deserves it today?",
            "Thank you for … — you deserve more recognition than you ask for."
        ),
        (
            "If today were your last chance, who would you most regret not thanking?",
            "Thank you for … — I'd regret never saying it."
        ),
        (
            "Who changed your life in a way they probably don't even know?",
            "Thank you for changing my life when you…"
        ),
        (
            "Who would be surprised to receive a thank you from you today?",
            "Thank you for … — this might surprise you, but it mattered."
        ),
        (
            "Who invested in you before there was any reason to?",
            "Thank you for investing in me when…"
        ),
        (
            "Who carried you through a difficult season?",
            "Thank you for carrying me through … when things were hard."
        ),
        (
            "Who makes your life better simply by being in it?",
            "Thank you for making my life better simply by being in it — especially…"
        ),
        (
            "Who's the first person that comes to mind when you think, \"I couldn't have done it without them\"?",
            "Thank you — I couldn't have done it without you when…"
        ),
        (
            "If your children read one thank-you note from you years from now, who would you want it to be about?",
            "Thank you for … — this is the kind of note I'd want remembered."
        ),
        (
            "Who deserves public recognition today but will never ask for it?",
            "Thank you for … — you deserve to be recognized for this."
        ),
        (
            "Who gave you a gift that money could never buy?",
            "Thank you for giving me … — something money could never buy."
        ),
        (
            "Who has consistently shown up for you over the years?",
            "Thank you for consistently showing up for me over the years, especially…"
        ),
    ]

    private static let subjects: [String] = [
        "It's Gratitude Friday",
        "Happy Gratitude Friday",
        "Gratitude Friday is here",
        "Your weekly Gratitude Friday reminder",
        "Gratitude Friday - Time to say thanks",
    ]

    private static let supportingBody =
        "Take a quiet moment with this question. When someone comes to mind, send them a short appreciation — it only takes a minute, and it can change their day."

    static let all: [Prompt] = questions.enumerated().map { index, pair in
        Prompt(
            subject: subjects[index % subjects.count],
            headline: pair.headline,
            body: supportingBody,
            preheader: pair.headline,
            starterIdea: pair.starter
        )
    }

    /// Matches web `fridayWeekNumber` (Sunday-based week-of-year).
    static func weekNumber(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        guard let startOfYear = calendar.date(from: startComponents) else { return 1 }

        let daysSinceStart = calendar.dateComponents([.day], from: startOfYear, to: date).day ?? 0
        // JS Date#getDay: 0 = Sunday … 6 = Saturday
        let jsStartWeekday = calendar.component(.weekday, from: startOfYear) - 1
        let value = (Double(daysSinceStart) + Double(jsStartWeekday) + 1) / 7.0
        return Int(ceil(value))
    }

    static func prompt(for date: Date = Date(), calendar: Calendar = .current) -> Prompt {
        let index = weekNumber(for: date, calendar: calendar) % all.count
        return all[index]
    }

    /// Next Friday at 9:00 local (or today if still before 9:00 on Friday).
    static func nextFridayNineAM(from date: Date = Date(), calendar: Calendar = .current) -> Date {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday

        let weekday = cal.component(.weekday, from: date) // 1 = Sunday … 6 = Friday
        var daysUntilFriday = (6 - weekday + 7) % 7
        if daysUntilFriday == 0 {
            let todayNine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            if date >= todayNine {
                daysUntilFriday = 7
            }
        }

        let day = cal.date(byAdding: .day, value: daysUntilFriday, to: date) ?? date
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }
}
