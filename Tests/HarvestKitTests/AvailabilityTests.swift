import Foundation
import Testing
@testable import HarvestKit

@MainActor
struct AvailabilityTests {
    private func tracker(_ suite: String) async -> TimeTracker {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let tracker = TimeTracker(service: DemoHarvestService(includesArchivedWork: true), accountName: "Test",
                                  favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
                                  meetingMemory: MeetingMemory(defaults: defaults),
                                  contextMemory: ContextMemory(defaults: defaults), isDemo: true, defaults: defaults)
        await tracker.refresh(force: true)
        return tracker
    }

    private let springDesign = TaskKey(projectID: 107, taskID: 11)

    @Test func archivedAssignmentsAreKeptApartFromTrackableOnes() {
        let open = ProjectAssignment(id: 1, project: .init(id: 1, name: "Open"), client: nil, taskAssignments: [
            .init(id: 1, task: NamedRef(id: 10, name: "Design")),
            .init(id: 2, isActive: false, task: NamedRef(id: 11, name: "Old task")),
        ])
        let closed = ProjectAssignment(id: 2, isActive: false, project: .init(id: 2, name: "Closed"), client: nil,
                                       taskAssignments: [.init(id: 3, task: NamedRef(id: 10, name: "Design"))])
        let trackable = ProjectAssignment.trackableTasks(from: [open, closed]).map(\.key)
        let archived = ProjectAssignment.archivedTasks(from: [open, closed])
        #expect(trackable == [TaskKey(projectID: 1, taskID: 10)])
        #expect(archived[TaskKey(projectID: 1, taskID: 11)]?.kind == .taskArchived)
        #expect(archived[TaskKey(projectID: 2, taskID: 10)]?.kind == .projectArchived)
    }

    @Test func archivedFavoritesStayAndSayWhy() async {
        let tracker = await tracker("AvailabilityTests.favorites")
        tracker.favorites.toggle(springDesign)
        tracker.favorites.toggle(TaskKey(projectID: 999, taskID: 1)) // never heard of
        #expect(tracker.favoriteTasks.map(\.key) == [springDesign])
        #expect(tracker.favoriteTasks.first?.project.name == "Spring Campaign")
        #expect(tracker.unavailability(of: springDesign)?.kind == .projectArchived)
        #expect(tracker.unavailability(of: TaskKey(projectID: 999, taskID: 1))?.kind == .notAssigned)
        #expect(tracker.isAvailable(TaskKey(projectID: 101, taskID: 11)))
    }

    @Test func archivedTasksCantBeStartedOrAddedTo() async {
        let tracker = await tracker("AvailabilityTests.start")
        let task = tracker.favoriteTasks.first ?? TrackableTask(
            project: NamedRef(id: 107, name: "Spring Campaign"), client: nil, task: NamedRef(id: 11, name: "Design"))
        let running = tracker.running?.key
        await tracker.toggle(task)
        #expect(tracker.running?.key == running)
        #expect(tracker.errorMessage?.contains("archived") == true)
        let added = await tracker.addEntry(task: task, on: LocalDate(), notes: "", hours: 1)
        #expect(added == nil)
    }

    @Test func lockedEntriesCantChange() async {
        let tracker = await tracker("AvailabilityTests.locked")
        let locked = tracker.entries.first { $0.lock != nil }!
        await tracker.deleteEntry(locked)
        #expect(tracker.entries.contains { $0.id == locked.id })
        #expect(tracker.errorMessage?.hasPrefix("Can't delete this entry") == true)
        await tracker.updateEntry(locked, task: tracker.task(for: locked), notes: "changed", hours: 1)
        #expect(tracker.entries.first { $0.id == locked.id }?.notes != "changed")
        await tracker.toggle(locked)
        #expect(tracker.running?.id != locked.id)
        #expect(tracker.cantChangeMessage(locked) != nil)
    }

    @Test func favoritesNamesAreRememberedForLater() async {
        let suite = "AvailabilityTests.remember"
        let tracker = await tracker(suite)
        let key = TaskKey(projectID: 101, taskID: 11)
        tracker.favorites.toggle(key)
        await tracker.refresh(force: true)
        let remembered = RememberedTasks.load(from: UserDefaults(suiteName: suite)!)
        #expect(remembered[key]?.project.name == "Website Redesign")
    }
}
