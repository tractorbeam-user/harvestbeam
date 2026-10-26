import Foundation

/// Short words for why a task is offered: when you last did it, or the habit
/// behind a suggestion. Shown at the end of each row in the ask box's list.
public enum Reasons {
    /// "today", "yesterday", "Thursday" (this past week) or "Oct 12".
    public static func lastTracked(_ day: LocalDate, today: LocalDate) -> String {
        switch day.days(until: today) {
        case ...0: return "today"
        case 1: return "yesterday"
        case 2...6: return day.date().formatted(.dateTime.weekday(.wide))
        default: return day.date().formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// "usually Mondays" when you've done it on two or more of the last four
    /// of today's weekday; otherwise "4× in 4 weeks"; nil when it's rare.
    public static func habit(days: Set<LocalDate>, today: LocalDate) -> String? {
        let recent = days.filter { $0 < today && $0.days(until: today) <= 28 }
        let sameWeekday = recent.filter { $0.weekday == today.weekday }
        if sameWeekday.count >= 2 {
            let name = Calendar.current.standaloneWeekdaySymbols[today.weekday - 1]
            return "usually \(name)s"
        }
        return recent.count >= 2 ? "\(recent.count)× in 4 weeks" : nil
    }
}

extension TimeTracker {
    /// When you last tracked `key`, in words; nil if it's not in loaded history.
    public func lastTrackedLabel(_ key: TaskKey, today: LocalDate = LocalDate()) -> String? {
        // `entries` is newest first.
        entries.first { $0.key == key && $0.spentDate <= today }
            .map { Reasons.lastTracked($0.spentDate, today: today) }
    }

    /// Why `key` is suggested, from the days you've tracked it lately.
    public func habitLabel(_ key: TaskKey, today: LocalDate = LocalDate()) -> String? {
        Reasons.habit(days: Set(entries.lazy.filter { $0.key == key }.map(\.spentDate)), today: today)
    }
}
