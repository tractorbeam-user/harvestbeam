import Foundation
import Testing
@testable import HarvestKit

@MainActor
struct FutureEntriesTests {
    @Test func entriesLoggedAheadSurviveARefresh() async {
        let defaults = UserDefaults(suiteName: "FutureEntriesTests")!
        defaults.removePersistentDomain(forName: "FutureEntriesTests")
        let tracker = TimeTracker(
            service: DemoHarvestService(), accountName: "Test",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults), isDemo: true
        )
        await tracker.refresh(force: true)
        let tomorrow = LocalDate().adding(days: 1)
        let task = tracker.tasks[0]
        let added = await tracker.addEntry(task: task, on: tomorrow, notes: "Planning ahead", hours: 1)
        #expect(added != nil)
        await tracker.refresh(force: true)
        #expect(tracker.entries(on: tomorrow).contains { $0.id == added?.id })
    }
}
