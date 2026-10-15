import Foundation

/// A calendar day with no time or time zone, matching Harvest's `spent_date` ("2026-10-15").
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date = .now, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func adding(days: Int, calendar: Calendar = .current) -> LocalDate {
        LocalDate(calendar.date(byAdding: .day, value: days, to: date(in: calendar))!, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDate, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(in: calendar), to: other.date(in: calendar)).day ?? 0
    }

    public func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date(in: calendar))
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let string = try decoder.singleValueContainer().decode(String.self)
        guard let value = LocalDate(string: string) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(string)"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
