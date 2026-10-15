import Foundation
import Testing
@testable import HarvestKit

struct RankingTests {
    let calendar = Calendar(identifier: .gregorian)
    let today = LocalDate(year: 2026, month: 10, day: 15) // a Thursday

    func entry(_ id: Int, project: Int, task: Int, daysAgo: Int, minute: Int = 0) -> TimeEntry {
        let day = today.adding(days: -daysAgo)
        let stamp = day.date(in: calendar).addingTimeInterval(Double(9 * 3600 + minute * 60))
        return TimeEntry(
            id: id, spentDate: day,
            project: NamedRef(id: project, name: "P\(project)"), task: NamedRef(id: task, name: "T\(task)"),
            client: nil, hours: 1, createdAt: stamp, updatedAt: stamp
        )
    }

    @Test func recentIsNewestFirstAndDistinct() {
        let entries = [
            entry(1, project: 1, task: 1, daysAgo: 3),
            entry(2, project: 2, task: 2, daysAgo: 0, minute: 10),
            entry(3, project: 1, task: 1, daysAgo: 0, minute: 30),
            entry(4, project: 3, task: 3, daysAgo: 1),
        ]
        let keys = Ranking.recent(from: entries, limit: 5)
        #expect(keys == [
            TaskKey(projectID: 1, taskID: 1),
            TaskKey(projectID: 2, taskID: 2),
            TaskKey(projectID: 3, taskID: 3),
        ])
    }

    @Test func recentSkipsExcluded() {
        let entries = [entry(1, project: 1, task: 1, daysAgo: 0), entry(2, project: 2, task: 2, daysAgo: 1)]
        let keys = Ranking.recent(from: entries, excluding: [TaskKey(projectID: 1, taskID: 1)])
        #expect(keys == [TaskKey(projectID: 2, taskID: 2)])
    }

    @Test func suggestionsFavorFrequentAndRecentUse() {
        var entries: [TimeEntry] = []
        // Task A: used often, but a month ago. Task B: a few times this week.
        for i in 0..<6 { entries.append(entry(100 + i, project: 1, task: 1, daysAgo: 28 + i)) }
        for i in 0..<3 { entries.append(entry(200 + i, project: 2, task: 2, daysAgo: i + 1)) }
        // Task C: once, long ago.
        entries.append(entry(300, project: 3, task: 3, daysAgo: 55))

        let keys = Ranking.suggested(from: entries, today: today, limit: 3)
        #expect(keys.first == TaskKey(projectID: 2, taskID: 2))
        #expect(keys.last == TaskKey(projectID: 3, taskID: 3))
    }

    @Test func sameWeekdayGetsABump() {
        // Both used once, equally long ago (7 vs 6 days); only one on a Thursday.
        let entries = [entry(1, project: 1, task: 1, daysAgo: 7), entry(2, project: 2, task: 2, daysAgo: 6)]
        let keys = Ranking.suggested(from: entries, today: today)
        #expect(keys.first == TaskKey(projectID: 1, taskID: 1))
    }

    @Test func searchMatchesEveryWordAcrossFields() {
        let tasks = [
            TrackableTask(project: NamedRef(id: 1, name: "Website Redesign"), projectCode: "TB-WEB",
                          client: NamedRef(id: 9, name: "Tractorbeam"), task: NamedRef(id: 1, name: "Design")),
            TrackableTask(project: NamedRef(id: 2, name: "Brand Refresh"), client: NamedRef(id: 8, name: "Acme"),
                          task: NamedRef(id: 1, name: "Design")),
            TrackableTask(project: NamedRef(id: 1, name: "Website Redesign"), client: NamedRef(id: 9, name: "Tractorbeam"),
                          task: NamedRef(id: 2, name: "Development")),
        ]
        #expect(Ranking.search("des acme", in: tasks).map(\.project.id) == [2])
        #expect(Ranking.search("tb-web", in: tasks).map(\.task.name) == ["Design"])
        #expect(Ranking.search("dev", in: tasks).first?.task.name == "Development")
        #expect(Ranking.search("zzz", in: tasks).isEmpty)
        #expect(Ranking.search("   ", in: tasks).isEmpty)
    }

    @Test func searchIgnoresCaseAndAccents() {
        let tasks = [TrackableTask(project: NamedRef(id: 1, name: "Café Menu"), client: nil, task: NamedRef(id: 1, name: "Résumé"))]
        #expect(Ranking.search("RESUME cafe", in: tasks).count == 1)
    }

    @Test func runningEntryElapsedCountsFromTimerStart() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let running = TimeEntry(
            id: 1, spentDate: today, project: NamedRef(id: 1, name: "P"), task: NamedRef(id: 1, name: "T"), client: nil,
            hours: 0.5, hoursWithoutTimer: 0.5, isRunning: true, timerStartedAt: start
        )
        #expect(running.elapsed(at: start.addingTimeInterval(600)) == 1800 + 600)
        #expect(TimeFormat.clock(3725) == "1:02:05")
        #expect(TimeFormat.hoursMinutes(3725) == "1:02")
    }

    @Test func decodesHarvestTimeEntryJSON() throws {
        let json = """
        {"id":636709355,"spent_date":"2026-10-15","hours":0.83,"hours_without_timer":0.5,"notes":null,
         "is_running":true,"timer_started_at":"2026-10-15T14:10:00Z",
         "created_at":"2026-10-15T13:00:00Z","updated_at":"2026-10-15T14:10:00Z",
         "project":{"id":14307913,"name":"Marketing Website","code":"MW"},
         "task":{"id":8083365,"name":"Graphic Design"},"client":{"id":5735774,"name":"ABC Corp","currency":"USD"},
         "user":{"id":1782959,"name":"Kim Allen"}}
        """
        let entry = try HarvestClient.decoder.decode(TimeEntry.self, from: Data(json.utf8))
        #expect(entry.key == TaskKey(projectID: 14307913, taskID: 8083365))
        #expect(entry.spentDate == today)
        #expect(entry.isRunning)
        #expect(entry.client?.name == "ABC Corp")
    }
}

struct LocalDateTests {
    @Test func ordinalAndWeekdayMatchCalendar() {
        let calendar = Calendar(identifier: .gregorian)
        var day = LocalDate(year: 2023, month: 12, day: 25)
        for _ in 0..<800 {
            let next = day.adding(days: 1)
            #expect(day.days(until: next) == 1)
            #expect(LocalDate(day.date(in: calendar).addingTimeInterval(36 * 3600), calendar: calendar) == next)
            #expect(day.weekday == calendar.component(.weekday, from: day.date(in: calendar)))
            day = next
        }
        #expect(LocalDate(year: 1970, month: 1, day: 1).ordinal == 0)
        #expect(LocalDate(year: 2026, month: 10, day: 15).startOfWeek(firstWeekday: 2) == LocalDate(year: 2026, month: 10, day: 12))
        #expect(LocalDate(year: 2026, month: 10, day: 15).startOfWeek(firstWeekday: 1) == LocalDate(year: 2026, month: 10, day: 11))
    }
}

struct MenuBarDisplayTests {
    @Test func truncatesAtTheEndOrMiddle() {
        let text = "Digital Products Redesign"
        #expect(MenuBarDisplay.truncate(text, to: 0, style: .end) == text)
        #expect(MenuBarDisplay.truncate(text, to: 12, style: .end) == "Digital Pro…")
        #expect(MenuBarDisplay.truncate(text, to: 12, style: .middle) == "Digita…esign")
        #expect(MenuBarDisplay.truncate("Short", to: 12, style: .end) == "Short")
    }
}
