import Testing
@testable import HarvestKit

struct ParseHoursTests {
    func minutes(_ text: String) -> Int? {
        TimeFormat.parseHours(text).map { Int(($0 * 60).rounded()) }
    }

    @Test func clockStyle() {
        #expect(minutes("0:25") == 25)
        #expect(minutes(":25") == 25)   // the 0 deleted, as people do
        #expect(minutes("1:30") == 90)
        #expect(minutes("2:") == 120)
        #expect(minutes(" 0 : 25 ") == 25)
        #expect(minutes(":") == nil)
        #expect(minutes("0:75") == nil)
    }

    @Test func unitsAndDecimals() {
        #expect(minutes("25m") == 25)
        #expect(minutes("25 min") == 25)
        #expect(minutes("45mins") == 45)
        #expect(minutes("1h") == 60)
        #expect(minutes("1hr") == 60)
        #expect(minutes("1h30m") == 90)
        #expect(minutes("1h30") == 90)
        #expect(minutes("1 h 15") == 75)
        #expect(minutes("1.5") == 90)
        #expect(minutes(".25") == 15)
    }

    @Test func nonsenseAndNegatives() {
        #expect(minutes("") == nil)
        #expect(minutes("abc") == nil)
        #expect(minutes("-1") == nil)
        #expect(minutes("-0:25") == nil)
        #expect(minutes("1h90") == nil)
    }
}
