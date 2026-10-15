import Foundation

public enum TimeFormat {
    /// "1:05:09", for the live timer.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// "1:05", Harvest's own hours:minutes style.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        // Nearest minute, like Harvest's own apps (rounding down read a minute
        // behind them half the time).
        let minutes = Int((max(0, seconds) / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
