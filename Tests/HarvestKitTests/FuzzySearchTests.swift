import Foundation
import Testing
@testable import HarvestKit

struct FuzzySearchTests {
    func task(_ project: Int, _ projectName: String, _ taskID: Int, _ taskName: String, client: String? = nil) -> TrackableTask {
        TrackableTask(project: NamedRef(id: project, name: projectName), client: client.map { NamedRef(id: project * 10, name: $0) },
                      task: NamedRef(id: taskID, name: taskName))
    }

    var tasks: [TrackableTask] {
        [
            task(1, "Website Redesign", 1, "Design"),
            task(1, "Website Redesign", 2, "Meetings"),
            task(2, "Internal", 3, "Research"),
            task(2, "Internal", 4, "Admin"),
        ]
    }

    func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }

    @Test func editDistanceCountsSwapsAsOne() {
        #expect(Ranking.editDistance(scalars("desgin"), scalars("design"), limit: 2) == 1)
        #expect(Ranking.editDistance(scalars("researhc"), scalars("research"), limit: 2) == 1)
        #expect(Ranking.editDistance(scalars("resarch"), scalars("research"), limit: 2) == 1)
        #expect(Ranking.editDistance(scalars("design"), scalars("design"), limit: 1) == 0)
        #expect(Ranking.editDistance(scalars("dzsxgn"), scalars("design"), limit: 1) == nil)
        #expect(Ranking.editDistance(scalars("ab"), scalars("abcde"), limit: 2) == nil)
    }

    @Test func allowedEditsGrowWithLength() {
        #expect(Ranking.allowedEdits(forLength: 3) == 0)
        #expect(Ranking.allowedEdits(forLength: 4) == 1)
        #expect(Ranking.allowedEdits(forLength: 7) == 1)
        #expect(Ranking.allowedEdits(forLength: 8) == 2)
    }

    @Test func typosStillFindTasks() {
        #expect(Ranking.search("researhc", in: tasks).first?.task.name == "Research")
        #expect(Ranking.search("reserach", in: tasks).first?.task.name == "Research")
        #expect(Ranking.search("desgin", in: tasks).first?.task.name == "Design")
        #expect(Ranking.search("meetigns", in: tasks).first?.task.name == "Meetings")
        #expect(Ranking.search("websiet", in: tasks).count == 2)
    }

    @Test func typosMatchEveryWordAcrossFields() {
        #expect(Ranking.search("desgin websiet", in: tasks).map(\.task.name) == ["Design"])
        #expect(Ranking.search("researhc internl", in: tasks).map(\.task.name) == ["Research"])
    }

    @Test func tooManyEditsFindNothing() {
        #expect(Ranking.search("dsgnn", in: tasks).isEmpty)
        #expect(Ranking.search("rxsxaxch", in: tasks).isEmpty)
    }

    @Test func shortQueriesStayExact() {
        // "dsn" is one edit from nothing useful and three letters, so no typo matching.
        #expect(Ranking.search("dsn", in: tasks).isEmpty)
        #expect(Ranking.search("adm", in: tasks).map(\.task.name) == ["Admin"])
        let short = [task(1, "Ops", 1, "Ops")]
        #expect(Ranking.search("op", in: short).count == 1)
        #expect(Ranking.search("ups", in: short).isEmpty)
    }

    @Test func exactMatchesRankAboveTypos() {
        let tasks = [
            task(1, "Studio", 1, "Desing Review"), // a typo in the task name itself
            task(2, "Studio", 2, "Design", client: "Acme"),
            task(3, "Design Sprint", 3, "Facilitation"),
        ]
        // "desing" matches task 1 exactly and tasks 2 and 3 only with a swap.
        #expect(Ranking.search("desing", in: tasks).map(\.task.id) == [1, 2, 3])
        // Even heavy use and a star don't lift a typo match over an exact one.
        let boosted = TaskKey(projectID: 2, taskID: 2)
        let results = Ranking.search("desing", in: tasks, usage: [boosted: 50], favorites: [boosted])
        #expect(results.first?.task.id == 1)
        // A substring match in the client name still beats a typo in the task name.
        let substring = [task(1, "X", 1, "Desgin"), task(2, "Y", 2, "Other", client: "Bigdesign Co")]
        #expect(Ranking.search("design", in: substring).map(\.task.id) == [2, 1])
    }

    @Test func quickPlanToleratesTypos() {
        let tasks = [
            task(1, "Context", 1, "Product Design"),
            task(1, "Context", 2, "Meetings or Calls"),
            task(2, "Internal", 3, "Research"),
        ]
        let index = Ranking.SearchIndex(tasks: tasks)
        let plan = DayPlanner.planWithKeywords("20 min on researhc, 1h context desgin, meetigns 30 min") { index.search($0) }
        #expect(plan.map(\.task.key) == [tasks[2].key, tasks[0].key, tasks[1].key])
        #expect(plan.map(\.hours) == [20.0 / 60, 1, 0.5])
    }

    @Test func fastEnoughForThousandsOfTasks() {
        let words = ["design", "research", "meetings", "development", "admin", "support", "planning", "review", "content", "strategy"]
        var many: [TrackableTask] = []
        for i in 0..<5000 {
            many.append(task(i / 10, "Project \(words[i % 7]) \(i / 10)", i, "\(words[i % 10]) \(words[(i / 3) % 10])",
                             client: "Client \(i % 50)"))
        }
        let index = Ranking.SearchIndex(tasks: many)
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in ["r", "re", "res", "rese", "resea", "researhc", "researhc desgin", "meetigns"] {
                _ = index.search(query)
            }
        }
        #expect(!index.search("researhc").isEmpty)
        #expect(elapsed < .seconds(2))
    }
}
