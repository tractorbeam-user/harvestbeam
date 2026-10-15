import Foundation

public enum TimeFormat {
    /// "1:05:09", for the live timer.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
    }

    /// "1:05", Harvest's own hours:minutes style.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
