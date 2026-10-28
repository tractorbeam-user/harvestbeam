import Foundation

public enum TimeFormat {
    /// "1:05:09", for the live timer.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// What someone types for a length, in hours: "1:30", ":25", "0:25",
    /// "1.5", "25m", "25 min", "1h", "1h30m", "1 h 30". Nil when it can't be
    /// read, or is negative.
    public static func parseHours(_ text: String) -> Double? {
        let s = text.lowercased().filter { !$0.isWhitespace }
        guard !s.isEmpty, !s.hasPrefix("-") else { return nil }
        func number(_ part: Substring) -> Double? { part.isEmpty ? 0 : Double(part) }
        if s.contains(":") {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let h = number(parts[0]), let m = number(parts[1]),
                  !(parts[0].isEmpty && parts[1].isEmpty), h >= 0, (0..<60).contains(m) else { return nil }
            return h + m / 60
        }
        // "1h30m", "1h30", "1h", "25m", "25min"
        var rest = Substring(s)
        var hours = 0.0
        var sawUnit = false
        if let h = rest.firstIndex(of: "h") {
            guard let value = Double(rest[..<h]) else { return nil }
            hours = value
            rest = rest[rest.index(after: h)...]
            if rest.hasPrefix("rs") { rest = rest.dropFirst(2) } else if rest.hasPrefix("r") { rest = rest.dropFirst() }
            sawUnit = true
        }
        for suffix in ["mins", "min", "m"] where rest.hasSuffix(suffix) {
            rest = rest.dropLast(suffix.count)
            sawUnit = true
            guard let minutes = Double(rest), minutes >= 0 else { return nil }
            return hours + minutes / 60
        }
        if sawUnit {
            // "1h30": the rest is minutes.
            guard let minutes = number(rest), minutes >= 0, minutes < 60 else { return nil }
            return hours + minutes / 60
        }
        guard let value = Double(s), value >= 0 else { return nil }
        return value
    }

    /// "1:05", Harvest's own hours:minutes style.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        // Nearest minute, like Harvest's own apps (rounding down read a minute
        // behind them half the time).
        let minutes = Int((max(0, seconds) / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
