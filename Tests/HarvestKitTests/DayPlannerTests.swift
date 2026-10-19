import Foundation
import Testing
@testable import HarvestKit

struct DayPlannerTests {
    func task(_ project: Int, _ projectName: String, _ taskID: Int, _ taskName: String, code: String? = nil) -> TrackableTask {
        TrackableTask(project: NamedRef(id: project, name: projectName), projectCode: code,
                      client: NamedRef(id: project * 10, name: "Client \(project)"), task: NamedRef(id: taskID, name: taskName))
    }

    @Test func splitsIntoClauses() {
        #expect(DayPlanner.clauses("Context design all morning, then an hour on LP. Client call") ==
            ["context design all morning", "an hour on lp", "client call"])
        #expect(DayPlanner.clauses("a\nb and then c; d") == ["a", "b", "c", "d"])
    }

    @Test func readsDurations() {
        #expect(DayPlanner.hours(in: "design 2h") == 2)
        #expect(DayPlanner.hours(in: "1.5 hours of dev") == 1.5)
        #expect(DayPlanner.hours(in: "call 30 min") == 0.5)
        #expect(DayPlanner.hours(in: "1:45 on audit") == 1.75)
        #expect(DayPlanner.hours(in: "an hour on qa") == 1)
        #expect(DayPlanner.hours(in: "half an hour of admin") == 0.5)
        #expect(DayPlanner.hours(in: "context all morning") == 3)
        #expect(DayPlanner.hours(in: "client call") == nil)
        #expect(DayPlanner.mentionsDuration("app stuff till lunch"))
        #expect(!DayPlanner.mentionsDuration("northwind meeting"))
    }

    @Test func keywordsDropFillers() {
        #expect(DayPlanner.keywords(in: "working on the context design for 2 hours") == ["context", "design"])
    }

    @Test func keywordFallbackPicksBestMatchPerClause() {
        let tasks = [
            task(1, "Context", 1, "Product Design", code: "TB-OP-01"),
            task(1, "Context", 2, "Meetings or Calls", code: "TB-OP-01"),
            task(2, "LP Analyst Website", 1, "Development", code: "LP-DP-01"),
        ]
        let index = Ranking.SearchIndex(tasks: tasks)
        let plan = DayPlanner.planWithKeywords("context design 2h, an hour of lp development, context call") {
            index.search($0)
        }
        #expect(plan.map(\.task.key) == [tasks[0].key, tasks[2].key, tasks[1].key])
        #expect(plan.map(\.hours) == [2, 1, nil])
    }

    @Test func keywordFallbackIgnoresWordsThatMatchNothing() {
        let tasks = [task(1, "Context", 1, "Product Design")]
        let index = Ranking.SearchIndex(tasks: tasks)
        let plan = DayPlanner.planWithKeywords("context zebra stuff") { index.search($0) }
        #expect(plan.first?.task.key == tasks[0].key)
    }
}

struct DayPlannerReconcileTests {
    let a = TrackableTask(project: NamedRef(id: 1, name: "TB Corporate"), client: nil, task: NamedRef(id: 1, name: "Product Design"))
    let b = TrackableTask(project: NamedRef(id: 1, name: "TB Corporate"), client: nil, task: NamedRef(id: 2, name: "Design Execution"))

    @Test func oneRequestIsOneEntryWithTheDurationTyped() {
        let model = [PlannedEntry(task: a, hours: 2, notes: "tb corporate"), PlannedEntry(task: b, hours: nil, notes: "")]
        let result = DayPlanner.reconcile(model, with: "add 10 min to tb corporate")
        #expect(result.count == 1)
        #expect(result[0].task == a)
        #expect(abs((result[0].hours ?? 0) - 10.0 / 60) < 0.001)
    }

    @Test func hoursNobodySaidAreDropped() {
        let model = [PlannedEntry(task: a, hours: 1, notes: "")]
        #expect(DayPlanner.reconcile(model, with: "tb corporate design").first?.hours == nil)
    }

    @Test func eachClauseKeepsItsOwnDuration() {
        let model = [PlannedEntry(task: a, hours: 5, notes: ""), PlannedEntry(task: b, hours: 5, notes: "")]
        let result = DayPlanner.reconcile(model, with: "2h on product design, then 30 min of execution")
        #expect(result.map(\.hours) == [2, 0.5])
    }

    @Test func addIsNotAKeyword() {
        #expect(DayPlanner.keywords(in: "add 10 min to tb corporate") == ["tb", "corporate"])
    }
}
