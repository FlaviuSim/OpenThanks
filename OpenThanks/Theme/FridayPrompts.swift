import Foundation

/// Gratitude Friday prompts — keep in sync with
/// `v0-gratitude-network/lib/friday-prompts.ts` (same week-index formula).
enum FridayPrompts {
    struct Prompt: Equatable {
        let subject: String
        let headline: String
        let body: String
        let preheader: String
    }

    private static let questions: [String] = [
        "Who made your week just a little bit better, even if they don't realize it?",
        "Who helped you solve a problem this week?",
        "Who made you smile or laugh when you needed it most?",
        "Who quietly supports you behind the scenes every week?",
        "Who inspired you through their actions this week?",
        "Who gave you an opportunity that changed your path—even years ago?",
        "Who believed in you before you fully believed in yourself?",
        "Who deserves a thank you you've never actually said out loud?",
        "Who taught you a lesson you're still using today?",
        "Who made a sacrifice that benefited you?",
        "Who checked in on you recently without wanting anything in return?",
        "Who has been consistently there for you, even in small ways?",
        "Who do you appreciate today more than you did a year ago?",
        "Who made your work easier this week?",
        "Who have you been meaning to thank for a long time?",
        "Who gave you confidence when you needed encouragement?",
        "Who helped shape the person you've become?",
        "Who made an ordinary moment feel special this week?",
        "Who rarely gets recognized but deserves it today?",
        "If today were your last chance, who would you most regret not thanking?",
        "Who changed your life in a way they probably don't even know?",
        "Who would be surprised to receive a thank you from you today?",
        "Who invested in you before there was any reason to?",
        "Who carried you through a difficult season?",
        "Who makes your life better simply by being in it?",
        "Who's the first person that comes to mind when you think, \"I couldn't have done it without them\"?",
        "If your children read one thank-you note from you years from now, who would you want it to be about?",
        "Who deserves public recognition today but will never ask for it?",
        "Who gave you a gift that money could never buy?",
        "Who has consistently shown up for you over the years?",
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

    static let all: [Prompt] = questions.enumerated().map { index, headline in
        Prompt(
            subject: subjects[index % subjects.count],
            headline: headline,
            body: supportingBody,
            preheader: headline
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
