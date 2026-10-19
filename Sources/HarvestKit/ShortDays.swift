import Foundation

/// Days earlier this week that are well short of a usual day, so the window
/// can nudge you to fill them in while you still remember.
public enum ShortDays {
    /// On by default; Preferences → General turns it off.
    public static let enabledKey = "prefs.shortDayNudge"
    /// Days you've dismissed the nudge for, as "2026-10-15" strings.
    public static let dismissedKey = "shortDays.dismissed"

    /// Short means under three quarters of a usual day.
    static let threshold = 0.75

    /// A usual day: weekly capacity over five days, or Harvest's default 35h week.
    public static func usualDay(weeklyCapacity: Int?) -> TimeInterval {
        Double(weeklyCapacity ?? 35 * 3600) / 5
    }

    /// Monday–Friday this week, before `today`, under the threshold; oldest first.
    public static func find(
        today: LocalDate, firstWeekday: Int, usualDay: TimeInterval, seconds: (LocalDate) -> TimeInterval
    ) -> [LocalDate] {
        guard usualDay > 0 else { return [] }
        let start = today.startOfWeek(firstWeekday: firstWeekday)
        return (0..<7).map { start.adding(days: $0) }
            .filter { $0 < today && (2...6).contains($0.weekday) && seconds($0) < usualDay * threshold }
    }
}

extension TimeTracker {
    /// Seconds in a usual workday for the signed-in person.
    public var usualDaySeconds: TimeInterval { ShortDays.usualDay(weeklyCapacity: user?.weeklyCapacity) }

    /// Short weekdays earlier this week.
    public func shortDays(today: LocalDate = LocalDate()) -> [LocalDate] {
        ShortDays.find(today: today, firstWeekday: firstWeekday, usualDay: usualDaySeconds) { seconds(on: $0) }
    }
}
