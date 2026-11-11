import Foundation
import Testing
@testable import HarvestKit

/// Each change to time, then undo: the entries are as they were. Then redo:
/// the change is back.
@MainActor
struct UndoTests {
    private func makeTracker() async -> TimeTracker {
        // Tests run side by side: each gets its own favorites.
        let suite = "UndoTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let tracker = TimeTracker(
            service: DemoHarvestService(), accountName: "Test",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults), isDemo: true
        )
        await tracker.refresh(force: true)
        return tracker
    }

    /// What matters about an entry for undo: its task, notes, time to the
    /// minute and whether it's running. Not its ID, which a recreated entry
    /// doesn't keep.
    private struct Shape: Hashable {
        let key: TaskKey
        let day: LocalDate
        let notes: String
        let minutes: Int
        let isRunning: Bool
    }

    private func shape(_ tracker: TimeTracker, on day: LocalDate = LocalDate()) -> [Shape] {
        tracker.entries(on: day).map {
            Shape(key: $0.key, day: $0.spentDate, notes: $0.notes ?? "",
                  minutes: Int(($0.elapsed() / 60).rounded()), isRunning: $0.isRunning)
        }.sorted { "\($0)" < "\($1)" }
    }

    /// Minutes may drift by one from rounding (Harvest keeps hours to two places).
    private func expectSame(_ a: [Shape], _ b: [Shape], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(a.count == b.count, sourceLocation: sourceLocation)
        for (x, y) in zip(a, b) {
            #expect(x.key == y.key && x.notes == y.notes && x.isRunning == y.isRunning, sourceLocation: sourceLocation)
            #expect(abs(x.minutes - y.minutes) <= 1, "\(x) vs \(y)", sourceLocation: sourceLocation)
        }
    }

    /// Does `change`, checks undo puts things back and redo does it again.
    private func roundTrip(_ tracker: TimeTracker, on day: LocalDate = LocalDate(),
                           sourceLocation: SourceLocation = #_sourceLocation,
                           _ change: () async -> Void) async {
        let before = shape(tracker, on: day)
        await change()
        let after = shape(tracker, on: day)
        #expect(after != before, "the change didn't change anything", sourceLocation: sourceLocation)
        #expect(tracker.canUndo, sourceLocation: sourceLocation)
        #expect(tracker.toast?.action == .undo, sourceLocation: sourceLocation)

        await tracker.undo()
        #expect(tracker.errorMessage == nil, sourceLocation: sourceLocation)
        expectSame(shape(tracker, on: day), before, sourceLocation: sourceLocation)
        #expect(tracker.canRedo, sourceLocation: sourceLocation)
        #expect(tracker.toast?.action == .redo, sourceLocation: sourceLocation)

        await tracker.redo()
        #expect(tracker.errorMessage == nil, sourceLocation: sourceLocation)
        expectSame(shape(tracker, on: day), after, sourceLocation: sourceLocation)

        // And back once more, through the new IDs redo may have made.
        await tracker.undo()
        #expect(tracker.errorMessage == nil, sourceLocation: sourceLocation)
        expectSame(shape(tracker, on: day), before, sourceLocation: sourceLocation)
    }

    private func otherTask(_ tracker: TimeTracker, than key: TaskKey) throws -> TrackableTask {
        let today = Set(tracker.entries(on: LocalDate()).map(\.key))
        return try #require(tracker.tasks.first { $0.key != key && !today.contains($0.key) })
    }

    private func stoppedEntry(_ tracker: TimeTracker) throws -> TimeEntry {
        try #require(tracker.entries(on: LocalDate()).first { !$0.isRunning && $0.lock == nil && $0.elapsed() > 1800 })
    }

    // MARK: Entries

    @Test func addEntry() async throws {
        let tracker = await makeTracker()
        let task = try otherTask(tracker, than: TaskKey(projectID: 0, taskID: 0))
        await roundTrip(tracker) {
            await tracker.addEntry(task: task, on: LocalDate(), notes: "Sketches", hours: 1.25)
        }
        #expect(tracker.redoLabel == "Added 1:15 to \(task.projectNameParts.name)")
    }

    @Test func editEntryTaskNotesAndHours() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        let task = try otherTask(tracker, than: entry.key)
        await roundTrip(tracker) {
            await tracker.updateEntry(entry, task: task, notes: "Changed", hours: entry.hours + 0.5)
        }
    }

    @Test func editNotes() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        await roundTrip(tracker) {
            await tracker.updateNotes("New notes", for: entry)
        }
    }

    @Test func editHoursOfARunningTimerStopsItAndUndoRestartsIt() async throws {
        let tracker = await makeTracker()
        let running = try #require(tracker.running)
        await roundTrip(tracker) {
            await tracker.updateEntry(running, task: tracker.task(for: running), notes: running.notes ?? "", hours: 0.25)
        }
        #expect(tracker.running?.id == running.id)
    }

    @Test func deleteEntry() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        await roundTrip(tracker) { await tracker.deleteEntry(entry) }
    }

    @Test func deleteRunningEntry() async throws {
        let tracker = await makeTracker()
        let running = try #require(tracker.running)
        await roundTrip(tracker) { await tracker.deleteEntry(running) }
        #expect(tracker.running != nil)
    }

    @Test func moveTimeIsOneUndo() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        let target = try otherTask(tracker, than: entry.key)
        await roundTrip(tracker) {
            #expect(await tracker.moveTime(20 * 60, from: entry, to: target))
        }
        #expect(tracker.redoLabel == "Moved 0:20 to \(target.projectNameParts.name)")
        // Both halves were one step: nothing else to undo.
        #expect(!tracker.canUndo)
    }

    @Test func moveTimeFromRunningTimer() async throws {
        let tracker = await makeTracker()
        let running = try #require(tracker.running)
        let target = try otherTask(tracker, than: running.key)
        await roundTrip(tracker) {
            #expect(await tracker.moveTime(10 * 60, from: running, to: target))
        }
        #expect(tracker.running?.id == running.id)
    }

    @Test func removeIdleTime() async throws {
        let tracker = await makeTracker()
        await roundTrip(tracker) {
            await tracker.removeIdleTime(15 * 60, keepRunning: false)
        }
        #expect(tracker.running != nil)
    }

    // MARK: Timers

    @Test func startingANewTimerUndoesToNothingAndRestartsThePrevious() async throws {
        let tracker = await makeTracker()
        let previous = try #require(tracker.running)
        let task = try otherTask(tracker, than: previous.key)
        await roundTrip(tracker) { await tracker.toggle(task) }
        #expect(tracker.running?.id == previous.id)
        #expect(!tracker.entries(on: LocalDate()).contains { $0.key == task.key })
    }

    @Test func undoingAStartKeepsTheEntryOnceItHasAMinute() async throws {
        let tracker = await makeTracker()
        await tracker.pause()
        let task = try otherTask(tracker, than: TaskKey(projectID: 0, taskID: 0))
        let added = try #require(await tracker.addEntry(task: task, on: LocalDate(), notes: "", hours: nil))
        // Pretend it's been running two minutes.
        tracker.upsert(TimeEntry(id: added.id, spentDate: added.spentDate, project: added.project, task: added.task,
                                 client: added.client, hours: 0, hoursWithoutTimer: 0, isRunning: true,
                                 timerStartedAt: .now.addingTimeInterval(-120)))
        await tracker.undo()
        let kept = try #require(tracker.entries(on: LocalDate()).first { $0.id == added.id })
        #expect(!kept.isRunning)
    }

    @Test func restartingAnEntryUndoesToStopped() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        await tracker.toggle(entry)
        #expect(tracker.running?.id == entry.id)
        await tracker.undo()
        #expect(tracker.running?.id != entry.id)
        #expect(tracker.entries.contains { $0.id == entry.id })
    }

    @Test func pause() async throws {
        let tracker = await makeTracker()
        let running = try #require(tracker.running)
        await roundTrip(tracker) { await tracker.pause() }
        #expect(tracker.running?.id == running.id)
    }

    // MARK: Favorites

    @Test func favoritesAddRemoveAndReorder() async throws {
        let tracker = await makeTracker()
        let (a, b, c) = (tracker.tasks[0].key, tracker.tasks[1].key, tracker.tasks[2].key)
        tracker.favorites.toggle(a)
        tracker.favorites.toggle(b)
        tracker.favorites.toggle(c)
        #expect(tracker.undoLabel?.hasPrefix("Added ") == true)

        tracker.favorites.place(c, before: a)
        #expect(tracker.favorites.keys == [c, a, b])
        #expect(tracker.undoLabel == "Reordered Favorites")
        await tracker.undo()
        #expect(tracker.favorites.keys == [a, b, c])
        await tracker.redo()
        #expect(tracker.favorites.keys == [c, a, b])

        tracker.favorites.toggle(a)
        #expect(tracker.undoLabel?.hasPrefix("Removed ") == true)
        await tracker.undo()
        #expect(tracker.favorites.keys == [c, a, b])

        await tracker.undo() // the reorder
        await tracker.undo() // adding c
        #expect(tracker.favorites.keys == [a, b])
    }

    // MARK: The list itself

    @Test func remembersTwentyStepsAndANewChangeClearsRedo() async throws {
        let tracker = await makeTracker()
        // 15 stars, then 10 unstarred: 25 changes.
        let keys = tracker.tasks.prefix(15).map(\.key)
        for key in keys { tracker.favorites.toggle(key) }
        for key in keys.prefix(10) { tracker.favorites.toggle(key) }
        var undone = 0
        while tracker.canUndo { await tracker.undo(); undone += 1 }
        #expect(undone == 20)
        // The first five stars are older than the 20 remembered.
        #expect(tracker.favorites.keys == Array(keys.prefix(5)))

        #expect(tracker.canRedo)
        tracker.favorites.toggle(keys[14])
        #expect(!tracker.canRedo)
    }

    @Test func signOutForgetsEverything() async throws {
        let tracker = await makeTracker()
        tracker.favorites.toggle(tracker.tasks[0].key)
        #expect(tracker.canUndo)
        tracker.signOut()
        #expect(!tracker.canUndo && !tracker.canRedo && tracker.toast == nil)
    }

    @Test func undoOfAnEntryGoneMeanwhileSaysSoAndDropsTheStep() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        tracker.favorites.toggle(tracker.tasks[0].key)
        await tracker.updateNotes("Edited", for: entry)
        // Deleted in Harvest's web app, say.
        tracker.removeEntry(id: entry.id)

        await tracker.undo()
        #expect(tracker.errorMessage?.contains("isn't in Harvest any more") == true)
        #expect(!tracker.canRedo)
        // The earlier change is still there to undo.
        #expect(tracker.undoLabel?.hasPrefix("Added ") == true)
    }

    @Test func undoOfAnEntryLockedMeanwhileSaysSo() async throws {
        let tracker = await makeTracker()
        let entry = try stoppedEntry(tracker)
        await tracker.updateNotes("Edited", for: entry)
        let edited = try #require(tracker.entries.first { $0.id == entry.id })
        tracker.upsert(TimeEntry(id: edited.id, spentDate: edited.spentDate, project: edited.project, task: edited.task,
                                 client: edited.client, hours: edited.hours, notes: edited.notes, isClosed: true))

        await tracker.undo()
        #expect(tracker.errorMessage?.contains("approved") == true)
        #expect(!tracker.canUndo && !tracker.canRedo)
    }
}
