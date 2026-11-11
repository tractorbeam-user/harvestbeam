import Foundation
import Testing
@testable import HarvestKit

@MainActor
struct MoveTimeTests {
    private func makeTracker() async -> TimeTracker {
        let defaults = UserDefaults(suiteName: "MoveTimeTests")!
        defaults.removePersistentDomain(forName: "MoveTimeTests")
        let tracker = TimeTracker(
            service: DemoHarvestService(), accountName: "Test",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults), isDemo: true
        )
        await tracker.refresh(force: true)
        return tracker
    }

    private func total(_ tracker: TimeTracker, on day: LocalDate) -> TimeInterval {
        tracker.entries(on: day).reduce(0) { $0 + $1.elapsed() }
    }

    @Test func movesTimeFromAStoppedEntry() async throws {
        let tracker = await makeTracker()
        let today = LocalDate()
        let entry = try #require(tracker.entries(on: today).first { !$0.isRunning && $0.elapsed() > 1800 })
        let target = try #require(tracker.tasks.first { $0.key != entry.key })
        let before = total(tracker, on: today)

        #expect(await tracker.moveTime(20 * 60, from: entry, to: target))

        let shortened = try #require(tracker.entries(on: today).first { $0.id == entry.id })
        #expect(abs(shortened.elapsed() - (entry.elapsed() - 1200)) < 60)
        #expect(tracker.entries(on: today).contains { $0.key == target.key && abs($0.elapsed() - 1200) < 60 })
        // Nothing gained or lost overall.
        #expect(abs(total(tracker, on: today) - before) < 60)
    }

    @Test func movesTimeFromARunningTimerAndKeepsItRunning() async throws {
        let tracker = await makeTracker()
        let today = LocalDate()
        let entry = try #require(tracker.running)
        let target = try #require(tracker.tasks.first { $0.key != entry.key })
        let moving = min(600, (entry.elapsed() / 2).rounded(.down))

        #expect(await tracker.moveTime(moving, from: entry, to: target))

        let still = try #require(tracker.entries(on: today).first { $0.id == entry.id })
        #expect(still.isRunning)
        #expect(abs(still.elapsed() - (entry.elapsed() - moving)) < 90)
        #expect(tracker.entries(on: today).contains { $0.key == target.key && !$0.isRunning })
    }

    @Test func refusesToMoveMoreThanTheEntryHas() async throws {
        let tracker = await makeTracker()
        let entry = try #require(tracker.entries(on: LocalDate()).first { !$0.isRunning })
        let target = try #require(tracker.tasks.first { $0.key != entry.key })
        let count = tracker.entries(on: LocalDate()).count

        #expect(await tracker.moveTime(entry.elapsed() + 3600, from: entry, to: target) == false)
        #expect(tracker.entries(on: LocalDate()).count == count)
        #expect(tracker.errorMessage != nil)
    }
}
