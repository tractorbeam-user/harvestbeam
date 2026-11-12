import Foundation
import Testing
@testable import HarvestKit

@MainActor
struct MergeEntriesTests {
    private func makeTracker() async -> TimeTracker {
        let defaults = UserDefaults(suiteName: "MergeEntriesTests")!
        defaults.removePersistentDomain(forName: "MergeEntriesTests")
        let tracker = TimeTracker(
            service: DemoHarvestService(), accountName: "Test",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults), isDemo: true
        )
        await tracker.refresh(force: true)
        return tracker
    }

    @Test func mergesSameTaskEntriesAndUndoesInOneStep() async throws {
        let tracker = await makeTracker()
        let today = LocalDate()
        let task = try #require(tracker.tasks.first { task in !tracker.entries(on: today).contains { $0.key == task.key } })
        let first = try #require(await tracker.addEntry(task: task, on: today, notes: "Homepage", hours: 0.5))
        _ = try #require(await tracker.addEntry(task: task, on: today, notes: "Nav", hours: 0.25))
        let countBefore = tracker.entries(on: today).count

        #expect(tracker.sameTaskEntries(as: first).count == 1)
        #expect(await tracker.mergeSameTaskEntries(into: first))

        let merged = tracker.entries(on: today).filter { $0.key == task.key }
        #expect(merged.count == 1)
        #expect(abs((merged.first?.hours ?? 0) - 0.75) < 0.01)
        #expect(merged.first?.notes == "Homepage; Nav")
        #expect(tracker.entries(on: today).count == countBefore - 1)

        await tracker.undo()
        #expect(tracker.entries(on: today).filter { $0.key == task.key }.count == 2)
        #expect(tracker.entries(on: today).count == countBefore)
    }
}
