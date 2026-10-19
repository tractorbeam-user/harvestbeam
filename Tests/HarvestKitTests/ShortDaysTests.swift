import Foundation
import Testing
@testable import HarvestKit

struct ShortDaysTests {
    let thursday = LocalDate(year: 2026, month: 10, day: 15)

    @Test func usualDayIsCapacityOverFive() {
        #expect(ShortDays.usualDay(weeklyCapacity: 40 * 3600) == 8 * 3600)
        #expect(ShortDays.usualDay(weeklyCapacity: nil) == 7 * 3600)
    }

    @Test func findsOnlyEarlierWeekdaysUnderThreeQuarters() {
        let tracked: [LocalDate: TimeInterval] = [
            thursday.adding(days: -3): 8 * 3600,   // Monday, full
            thursday.adding(days: -2): 5.9 * 3600, // Tuesday, under 6h
            thursday.adding(days: -1): 6 * 3600,   // Wednesday, exactly three quarters
        ]
        let short = ShortDays.find(today: thursday, firstWeekday: 2, usualDay: 8 * 3600) { tracked[$0] ?? 0 }
        // Today and the weekend never count.
        #expect(short == [thursday.adding(days: -2)])
    }

    @Test func emptyEarlierDaysCount() {
        let short = ShortDays.find(today: thursday, firstWeekday: 2, usualDay: 8 * 3600) { _ in 0 }
        #expect(short == [-3, -2, -1].map { thursday.adding(days: $0) })
    }
}
