import Foundation
import Testing
@testable import HarvestKit

struct TaskDefinitionTests {
    func task(_ id: Int, _ project: String, code: String? = nil, _ name: String = "General") -> TrackableTask {
        TrackableTask(project: NamedRef(id: id, name: project), projectCode: code, client: NamedRef(id: 1, name: "Tractorbeam"),
                      task: NamedRef(id: id * 10, name: name))
    }

    @Test func matchesByCodeInTheNameOrCode() {
        #expect(TaskDefinitions.definition(for: task(1, "[TB-DP-12] Billing"))?.name == "Billing")
        #expect(TaskDefinitions.definition(for: task(2, "Internal Hiring", code: "TB-DP-14"))?.name == "Hiring")
        #expect(TaskDefinitions.definition(for: task(3, "[tb-dp-1] Overhead"))?.code == "TB-DP-01")
        // A code beats a retired name.
        #expect(TaskDefinitions.definition(for: task(4, "[TB-DP-19] Business Dev"))?.code == "TB-DP-19")
        #expect(TaskDefinitions.definition(for: task(5, "[TB-DP-99] Mystery")) == nil)
        #expect(TaskDefinitions.definition(for: task(6, "Website Redesign", code: "TB-WEB")) == nil)
    }

    @Test func matchesPTOAndCrossDivisionalByName() {
        #expect(TaskDefinitions.definition(for: task(1, "PTO"))?.name == "PTO")
        #expect(TaskDefinitions.definition(for: task(2, "Time Off", "PTO - Vacation"))?.name == "PTO")
        #expect(TaskDefinitions.definition(for: task(3, "Cross-Divisional Processes, Training, & Development"))?.code == nil)
        #expect(TaskDefinitions.definition(for: task(3, "Cross-Divisional Processes, Training, & Development"))?.summary.contains("committees") == true)
        // "pto" inside a word isn't PTO.
        #expect(TaskDefinitions.definition(for: task(4, "Cryptography")) == nil)
    }

    @Test func knowsTheRetiredBuckets() throws {
        let generic = try #require(TaskDefinitions.definition(for: task(1, "Digital Products")))
        #expect(generic.isRetired)
        #expect(generic.detail.contains("[TB-DP-01]"))
        #expect(TaskDefinitions.definition(for: task(2, "Tractorbeam", code: "TB-DP"))?.isRetired == true)
        let bizDev = try #require(TaskDefinitions.definition(for: task(3, "Business Dev")))
        #expect(bizDev.isRetired)
        #expect(bizDev.detail.contains("[TB-DP-19]"))
    }

    @Test func searchFindsTasksByDescriptionBelowNameMatches() {
        let tasks = [
            task(1, "[TB-DP-12] Billing"),
            task(2, "[TB-DP-14] Hiring"),
            task(3, "[TB-DP-19] Business Development"),
            task(4, "Invoice Redesign", code: "ACME"),
            task(5, "Website", "Design"),
        ]
        let index = Ranking.SearchIndex(tasks: tasks)
        #expect(index.search("invoice").map(\.project.id) == [4, 1])
        #expect(index.search("interview").map(\.project.id) == [2])
        #expect(index.search("pitch deck").map(\.project.id) == [3])
        // Description words match whole-word prefixes only, and need three letters.
        #expect(index.search("de").map(\.project.id).contains(2) == false)
        #expect(index.search("voice").isEmpty || !index.search("voice").map(\.project.id).contains(1))
        // Favorites and usage don't lift a description match over a name match.
        #expect(index.search("invoice", usage: [tasks[0].key: 5], favorites: [tasks[0].key]).first?.project.id == 4)
    }
}
