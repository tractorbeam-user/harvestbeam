import Foundation
import Testing
@testable import HarvestKit

struct WeeklySummaryTests {
    // Monday 2026-11-09 … Sunday 2026-11-15.
    let monday = LocalDate(year: 2026, month: 11, day: 9)
    let acme = NamedRef(id: 2, name: "Acme Co")
    let tractorbeam = NamedRef(id: 1, name: "Tractorbeam")
    let brand = NamedRef(id: 103, name: "Brand Refresh")
    let app = NamedRef(id: 104, name: "Mobile App")
    let ops = NamedRef(id: 201, name: "[TB-DP-03] Operations")
    let design = NamedRef(id: 11, name: "Design")
    let qa = NamedRef(id: 16, name: "QA")
    let admin = NamedRef(id: 17, name: "Admin")

    private var nextID = 0
    private mutating func entry(
        _ day: LocalDate, _ project: NamedRef, _ task: NamedRef, _ client: NamedRef?, _ hours: Double, billable: Bool? = nil
    ) -> TimeEntry {
        nextID += 1
        return TimeEntry(id: nextID, spentDate: day, project: project, task: task, client: client, hours: hours, billable: billable)
    }

    /// Past week, so it's finished.
    let afterTheWeek = LocalDate(year: 2026, month: 11, day: 20)

    @Test mutating func totalsAndDays() {
        let entries = [
            entry(monday, brand, design, acme, 2),
            entry(monday, ops, admin, tractorbeam, 1.5),
            entry(monday.adding(days: 2), app, qa, acme, 3),
            entry(monday.adding(days: 7), app, qa, acme, 8), // next week: not counted
            entry(monday.adding(days: -1), app, qa, acme, 8), // last Sunday: not counted
        ]
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.total == 6.5 * 3600)
        #expect(s.days.count == 7)
        let byDay: [TimeInterval] = [12600, 0, 10800, 0, 0, 0, 0]
        #expect(s.days.map(\.seconds) == byDay)
        #expect(s.days.first?.date == monday)
        #expect(s.weekEnd == LocalDate(year: 2026, month: 11, day: 15))
        #expect(!s.isEmpty)
    }

    @Test mutating func groupsByClientThenProjectBiggestFirst() {
        let entries = [
            entry(monday, brand, design, acme, 2),
            entry(monday.adding(days: 1), app, qa, acme, 3),
            entry(monday.adding(days: 1), app, design, acme, 1),
            entry(monday, ops, admin, tractorbeam, 1.5),
            entry(monday, NamedRef(id: 300, name: "Loose"), admin, nil, 0.5),
        ]
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.clients.map(\.name) == ["Acme Co", "Tractorbeam", "No client"])
        #expect(s.clients[0].seconds == 6 * 3600)
        #expect(s.clients[0].projects.map(\.name) == ["Mobile App", "Brand Refresh"])
        let projectSeconds: [TimeInterval] = [14400, 7200]
        #expect(s.clients[0].projects.map(\.seconds) == projectSeconds)
        #expect(abs(s.share(s.clients[0].seconds) - 0.75) < 0.0001)
        // Shares of every client add up to the whole week.
        let shares: Double = s.clients.map { s.share($0.seconds) }.reduce(0, +)
        #expect(abs(shares - 1) < 0.0001)
    }

    @Test mutating func topTasksAreTheBiggestFive() {
        var entries: [TimeEntry] = []
        let hours: [Double] = [1, 6, 2, 5, 3, 4]
        for (i, hours) in hours.enumerated() {
            entries.append(entry(monday, NamedRef(id: 400 + i, name: "P\(i)"), design, acme, hours))
        }
        // Same task twice in the week adds up.
        entries.append(entry(monday.adding(days: 3), NamedRef(id: 400, name: "P0"), design, acme, 6.5))
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.topTasks.count == 5)
        #expect(s.topTasks.map(\.project) == ["P0", "P1", "P3", "P5", "P4"])
        #expect(s.topTasks[0].seconds == 7.5 * 3600)
    }

    @Test mutating func billableUsesHarvestsFlagFirst() {
        let entries = [
            entry(monday, brand, design, acme, 2, billable: true),
            // Harvest says non-billable even though it's client work.
            entry(monday, app, qa, acme, 1, billable: false),
            // Harvest says billable even though the name looks internal.
            entry(monday, ops, admin, tractorbeam, 0.5, billable: true),
        ]
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.billable == 2.5 * 3600)
        #expect(s.internal == 1 * 3600)
    }

    @Test mutating func withoutAFlagTractorbeamWorkIsInternal() {
        let entries = [
            entry(monday, brand, design, acme, 2),
            entry(monday, ops, admin, NamedRef(id: 9, name: "Someone Else"), 1), // [TB-DP-xx] code
            entry(monday, NamedRef(id: 202, name: "Website"), design, tractorbeam, 1.5), // Tractorbeam client
        ]
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.billable == 2 * 3600)
        #expect(s.internal == 2.5 * 3600)
        #expect(s.billable + s.internal == s.total)
    }

    @Test mutating func comparesWithLastWeekAndAUsualWeek() {
        var entries = [entry(monday, brand, design, acme, 30)]
        entries.append(entry(monday.adding(days: -7), brand, design, acme, 25))      // last week
        entries.append(entry(monday.adding(days: -14), brand, design, acme, 35))     // 2 weeks back
        // 3 weeks back is empty and doesn't drag the usual week down.
        entries.append(entry(monday.adding(days: -28), brand, design, acme, 36))     // 4 weeks back
        entries.append(entry(monday.adding(days: -35), brand, design, acme, 100))    // too far back
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek)
        #expect(s.previousTotal == 25 * 3600)
        #expect(s.change == 5 * 3600)
        #expect(s.comparesThrough == nil)
        #expect(s.usualTotal == TimeInterval(32 * 3600))
        #expect(s.changeFromUsual == TimeInterval(-2 * 3600))
    }

    @Test mutating func weekInProgressComparesToTheSameDayLastWeek() {
        let wednesday = monday.adding(days: 2)
        let entries = [
            entry(monday, brand, design, acme, 4),
            entry(wednesday, brand, design, acme, 4),
            entry(monday.adding(days: -7), brand, design, acme, 5),
            entry(wednesday.adding(days: -7), brand, design, acme, 1),
            entry(wednesday.adding(days: -6), brand, design, acme, 10), // last Thursday: not yet comparable
        ]
        let s = WeeklySummary.make(entries: entries, weekStart: monday, today: wednesday)
        #expect(s.comparesThrough == wednesday)
        #expect(s.previousTotal == 6 * 3600)
        #expect(s.change == 2 * 3600)
        // The usual week is still whole weeks.
        #expect(s.usualTotal == TimeInterval(16 * 3600))
    }

    @Test func emptyWeek() {
        let s = WeeklySummary.make(entries: [], weekStart: monday, today: afterTheWeek)
        #expect(s.isEmpty)
        #expect(s.usualTotal == nil)
        #expect(s.clients.isEmpty && s.topTasks.isEmpty)
        #expect(s.share(0) == 0)
        #expect(s.plainText.contains("No time tracked."))
    }

    @Test func runningTimerCountsUpToNow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let running = TimeEntry(id: 1, spentDate: monday, project: brand, task: design, client: acme, hours: 0,
                                hoursWithoutTimer: 1, isRunning: true, timerStartedAt: now.addingTimeInterval(-1800))
        let s = WeeklySummary.make(entries: [running], weekStart: monday, today: monday, now: now)
        #expect(s.total == 1.5 * 3600)
    }

    @Test mutating func plainTextReadsWell() {
        let entries = [
            entry(monday, brand, design, acme, 2, billable: true),
            entry(monday, ops, admin, tractorbeam, 1, billable: false),
            entry(monday.adding(days: -7), brand, design, acme, 4),
        ]
        let text = WeeklySummary.make(entries: entries, weekStart: monday, today: afterTheWeek).plainText
        #expect(text.hasPrefix("Weekly summary · Nov 9 – 15, 2026"))
        #expect(text.contains("Total: 3:00 (−1:00 vs last week, −1:00 vs a usual week)"))
        #expect(text.contains("Billable: 2:00 (67%) · Internal: 1:00 (33%)"))
        #expect(text.contains("• Acme Co — 2:00 (67%)"))
        #expect(text.contains("    ◦ Brand Refresh — 2:00"))
        #expect(text.contains("1. Design · Brand Refresh — 2:00"))
    }

    @Test func signedDifferences() {
        #expect(WeeklySummary.signed(3.25 * 3600) == "+3:15")
        #expect(WeeklySummary.signed(-65 * 60) == "−1:05")
        #expect(WeeklySummary.signed(20) == "±0:00")
    }
}
