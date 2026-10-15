import Foundation

/// A calendar day with no time or time zone, matching Harvest's `spent_date` ("2026-10-15").
public struct LocalDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Days since 1970-01-01. Cheap day arithmetic without going through
    /// `Calendar`, which is slow enough to matter when ranking every entry.
    public let ordinal: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        self.ordinal = era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `ordinal` (Howard Hinnant's civil_from_days).
    public init(ordinal: Int) {
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(year: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month: month, day: day)
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

    public func adding(days: Int) -> LocalDate {
        LocalDate(ordinal: ordinal + days)
    }

    /// The first day of this date's week, where `firstWeekday` uses `Calendar`
    /// numbering (1 = Sunday, 2 = Monday).
    public func startOfWeek(firstWeekday: Int) -> LocalDate {
        adding(days: -((weekday - firstWeekday + 7) % 7))
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: LocalDate) -> Int {
        other.ordinal - ordinal
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar`'s weekday numbering.
    public var weekday: Int {
        ((ordinal % 7 + 7) % 7 + 4) % 7 + 1 // 1970-01-01 was a Thursday
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.ordinal < rhs.ordinal
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
