import Foundation
import Testing
@testable import HarvestKit

/// A Harvest that remembers what it was asked to change, and can be set to
/// track start and end times, or to ignore new hours.
actor RecordingService: HarvestService {
    let timestamps: Bool
    let ignoresHours: Bool
    private(set) var lastUpdate: (hours: Double?, times: ClockTimes?)?
    private var entry: TimeEntry

    init(timestamps: Bool, ignoresHours: Bool = false, entry: TimeEntry) {
        self.timestamps = timestamps
        self.ignoresHours = ignoresHours
        self.entry = entry
    }

    func currentUser() async throws -> HarvestUser { HarvestUser(id: 1, firstName: "J", lastName: "R", email: "j@example.com") }
    func company() async throws -> Company { Company(baseUri: "https://x.harvestapp.com", name: "X", wantsTimestampTimers: timestamps) }
    func projectAssignments() async throws -> [ProjectAssignment] { [] }
    func timeEntries(userID: Int, from: LocalDate, to: LocalDate) async throws -> [TimeEntry] { [entry] }
    func startTimer(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?) async throws -> TimeEntry { entry }
    func createEntry(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?, hours: Double, times: ClockTimes?) async throws -> TimeEntry { entry }
    func restartTimer(id: Int) async throws -> TimeEntry { entry }
    func stopTimer(id: Int) async throws -> TimeEntry { entry }
    func updateNotes(id: Int, notes: String) async throws -> TimeEntry { entry }
    func deleteEntry(id: Int) async throws {}

    func updateEntry(id: Int, projectID: Int, taskID: Int, notes: String, hours: Double?, times: ClockTimes?) async throws -> TimeEntry {
        lastUpdate = (hours, times)
        var newHours = entry.hours
        if let times, let a = ClockTime.minutes(times.started), let b = ClockTime.minutes(times.ended) {
            newHours = Double(b - a) / 60
        } else if let hours, !timestamps, !ignoresHours {
            newHours = hours
        }
        entry = TimeEntry(id: entry.id, spentDate: entry.spentDate, project: entry.project, task: entry.task, client: nil,
                          hours: newHours, notes: notes, startedTime: times?.started ?? entry.startedTime,
                          endedTime: times?.ended ?? entry.endedTime)
        return entry
    }
}

@MainActor
struct EditEntryTests {
    let entry = TimeEntry(id: 7, spentDate: LocalDate(), project: NamedRef(id: 1, name: "P"), task: NamedRef(id: 2, name: "T"),
                          client: nil, hours: 34.0 / 60, startedTime: "9:00am", endedTime: "9:34am")
    let task = TrackableTask(project: NamedRef(id: 1, name: "P"), client: nil, task: NamedRef(id: 2, name: "T"))

    func tracker(_ service: RecordingService) async -> TimeTracker {
        let defaults = UserDefaults(suiteName: "EditEntryTests")!
        defaults.removePersistentDomain(forName: "EditEntryTests")
        let tracker = TimeTracker(service: service, accountName: "Test",
                                  favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
                                  meetingMemory: MeetingMemory(defaults: defaults),
                                  contextMemory: ContextMemory(defaults: defaults), isDemo: true)
        await tracker.refresh(force: true)
        return tracker
    }

    @Test func durationAccountsSendHours() async {
        let service = RecordingService(timestamps: false, entry: entry)
        let tracker = await tracker(service)
        await tracker.updateEntry(entry, task: task, notes: "", hours: 25.0 / 60)
        let sent = await service.lastUpdate
        #expect(sent?.hours == 25.0 / 60)
        #expect(sent?.times == nil)
        #expect(TimeFormat.hoursMinutes(tracker.entries.first!.hours * 3600) == "0:25")
        #expect(tracker.errorMessage == nil)
    }

    @Test func startAndEndAccountsMoveTheEndTime() async {
        let service = RecordingService(timestamps: true, entry: entry)
        let tracker = await tracker(service)
        await tracker.updateEntry(entry, task: task, notes: "", hours: 25.0 / 60)
        let sent = await service.lastUpdate
        #expect(sent?.times == ClockTimes(started: "9:00am", ended: "9:25am"))
        #expect(TimeFormat.hoursMinutes(tracker.entries.first!.hours * 3600) == "0:25")
        #expect(tracker.errorMessage == nil)
    }

    @Test func aLengthHarvestKeptIsReportedNotHidden() async {
        let service = RecordingService(timestamps: false, ignoresHours: true, entry: entry)
        let tracker = await tracker(service)
        await tracker.updateEntry(entry, task: task, notes: "", hours: 25.0 / 60)
        #expect(tracker.errorMessage?.hasPrefix("Harvest kept this entry at 0:34, not 0:25.") == true)
    }

    @Test func clockTimes() {
        #expect(ClockTime.minutes("9:05am") == 545)
        #expect(ClockTime.minutes("12:30 PM") == 750)
        #expect(ClockTime.minutes("12:10am") == 10)
        #expect(ClockTime.minutes("13:05") == 785)
        #expect(ClockTime.minutes("25:00") == nil)
        #expect(ClockTime.format(750) == "12:30pm")
        #expect(ClockTime.times(startingAt: "11:50am", hours: 0.5) == ClockTimes(started: "11:50am", ended: "12:20pm"))
        #expect(ClockTime.times(startingAt: "11:50pm", hours: 0.5) == nil) // past midnight
    }
}
