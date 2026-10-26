import Foundation
import Testing
@testable import HarvestKit

struct ReasonsTests {
    let monday = LocalDate(year: 2026, month: 10, day: 26)

    @Test func lastTrackedInWords() {
        #expect(Reasons.lastTracked(monday, today: monday) == "today")
        #expect(Reasons.lastTracked(monday.adding(days: -1), today: monday) == "yesterday")
        #expect(Reasons.lastTracked(monday.adding(days: -4), today: monday) == "Thursday")
        #expect(Reasons.lastTracked(monday.adding(days: -14), today: monday) == "Oct 12")
    }

    @Test func habitPrefersTheSameWeekday() {
        let mondays: Set = [monday.adding(days: -7), monday.adding(days: -14)]
        #expect(Reasons.habit(days: mondays, today: monday) == "usually Mondays")
        let scattered: Set = [monday.adding(days: -2), monday.adding(days: -9), monday.adding(days: -10)]
        #expect(Reasons.habit(days: scattered, today: monday) == "3× in 4 weeks")
        #expect(Reasons.habit(days: [monday.adding(days: -3)], today: monday) == nil)
        // Today and anything over four weeks back don't count.
        #expect(Reasons.habit(days: [monday, monday.adding(days: -35)], today: monday) == nil)
    }
}
