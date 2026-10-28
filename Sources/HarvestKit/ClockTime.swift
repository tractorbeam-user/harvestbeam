import Foundation

/// A start and end time, as Harvest writes them ("9:05am"), for accounts
/// that track start and end times instead of durations. On those accounts an
/// entry's hours are just the gap between the two, so changing the hours
/// means moving the end time.
public struct ClockTimes: Equatable, Sendable {
    public let started: String
    public let ended: String

    public init(started: String, ended: String) {
        self.started = started
        self.ended = ended
    }
}

public enum ClockTime {
    /// "9:05am", "12:30 PM" or "13:05" → minutes after midnight.
    public static func minutes(_ text: String) -> Int? {
        let s = text.lowercased().replacingOccurrences(of: " ", with: "")
        let pm = s.hasSuffix("pm"), am = s.hasSuffix("am")
        let digits = (am || pm) ? String(s.dropLast(2)) : s
        let parts = digits.split(separator: ":")
        guard parts.count == 2, var hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<60).contains(minute) else { return nil }
        if am || pm {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (pm ? 12 : 0)
        }
        guard (0..<24).contains(hour) else { return nil }
        return hour * 60 + minute
    }

    /// Minutes after midnight → "9:05am", Harvest's own style.
    public static func format(_ minutes: Int) -> String {
        let hour = minutes / 60, minute = minutes % 60
        return String(format: "%d:%02d%@", hour % 12 == 0 ? 12 : hour % 12, minute, hour < 12 ? "am" : "pm")
    }

    /// From `start`, lasting `hours`; nil when that runs past midnight.
    public static func times(startingAt start: String, hours: Double) -> ClockTimes? {
        guard let from = minutes(start) else { return nil }
        let to = from + Int((hours * 60).rounded())
        guard to < 24 * 60 else { return nil }
        return ClockTimes(started: format(from), ended: format(to))
    }

    /// From a moment on the clock, lasting `hours`.
    public static func times(from date: Date, hours: Double, calendar: Calendar = .current) -> ClockTimes? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return times(startingAt: format((c.hour ?? 0) * 60 + (c.minute ?? 0)), hours: hours)
    }
}
