import Foundation
import Testing
@testable import HarvestKit

struct MeetingMatcherTests {
    let pinstripes = NamedRef(id: 1, name: "Pinstripes")
    let astonBath = NamedRef(id: 2, name: "Aston Bath")
    let daf = NamedRef(id: 3, name: "DAF")

    var tasks: [TrackableTask] {
        [
            TrackableTask(project: NamedRef(id: 10, name: "Account Mgmt"), projectCode: "PS-DM-01", client: pinstripes, task: NamedRef(id: 1, name: "Meetings")),
            TrackableTask(project: NamedRef(id: 11, name: "Analytics"), projectCode: "PS-DM-02", client: pinstripes, task: NamedRef(id: 2, name: "Reporting")),
            TrackableTask(project: NamedRef(id: 20, name: "Analytics"), projectCode: "AB-DM-02", client: astonBath, task: NamedRef(id: 2, name: "Reporting")),
            TrackableTask(project: NamedRef(id: 30, name: "[DAF-DP-01] Website Design"), client: daf, task: NamedRef(id: 3, name: "Design")),
        ]
    }

    func entry(_ id: Int, project: Int, task: Int, notes: String?, day: LocalDate) -> TimeEntry {
        TimeEntry(id: id, spentDate: day, project: NamedRef(id: project, name: "P"), task: NamedRef(id: task, name: "T"),
                  client: nil, hours: 1, notes: notes)
    }

    func suggest(_ title: String, entries: [TimeEntry] = [], remembered: [String: TaskKey] = [:],
                 usage: [TaskKey: Double] = [:]) -> MeetingSuggestion? {
        MeetingMatcher.suggestion(for: title, tasks: tasks, entries: entries, remembered: remembered, usage: usage)
    }

    @Test func rememberedWinsOverEverything() {
        let key = TaskKey(projectID: 20, taskID: 2)
        let s = suggest("Pinstripes weekly sync", remembered: ["pinstripes weekly sync": key])
        #expect(s?.task.key == key)
        #expect(s?.reason == .remembered)
    }

    @Test func titleLoggedBeforeAsNotes() {
        let day = LocalDate(year: 2026, month: 10, day: 19)
        let s = suggest("Tractorbeam X Forseti | Intro",
                        entries: [entry(1, project: 11, task: 2, notes: "tractorbeam x forseti  | intro", day: day)])
        #expect(s?.task.key == TaskKey(projectID: 11, taskID: 2))
        #expect(s?.reason == .loggedBefore(day))
    }

    @Test func bracketedCodeMatchesCodeOrNamePrefix() {
        #expect(suggest("[DAF] Internal Review")?.task.project.id == 30)
        #expect(suggest("[DAF] Internal Review")?.reason == .projectCode("DAF"))
        #expect(suggest("Kickoff for PS-DM-02")?.task.project.id == 11)
    }

    @Test func codePrefixPicksTheMostUsed() {
        let s = suggest("[PS] status", usage: [TaskKey(projectID: 11, taskID: 2): 3])
        #expect(s?.task.project.id == 11)
    }

    @Test func clientNameNeedsUseOrAMeetingsTask() {
        // Pinstripes has a Meetings task, so it's suggested with no history.
        #expect(suggest("Pinstripes weekly sync")?.task.key == TaskKey(projectID: 10, taskID: 1))
        // Aston Bath has none and no history: no guess.
        #expect(suggest("Aston Bath GA4 review") == nil)
        let used = suggest("aston bath GA4 review", usage: [TaskKey(projectID: 20, taskID: 2): 1])
        #expect(used?.reason == .clientName("Aston Bath"))
    }

    @Test func projectNameNeedsTwoWordsOrItsClient() {
        let redesign = TrackableTask(project: NamedRef(id: 40, name: "Website Redesign"), client: daf, task: NamedRef(id: 4, name: "Design"))
        let s = MeetingMatcher.suggestion(for: "Website Redesign standup", tasks: tasks + [redesign], entries: [],
                                          remembered: [:], usage: [:])
        #expect(s?.reason == .projectName("Website Redesign"))
        // "Analytics" alone is too generic; with the client's name it's Aston Bath's.
        #expect(suggest("Analytics office hours") == nil)
        #expect(suggest("Aston Bath analytics review")?.task.project.id == 20)
    }

    @Test func sharedProjectNameNeedsItsClientOrOneInUse() {
        let arqline = NamedRef(id: 5, name: "Arqline")
        let search = [
            TrackableTask(project: NamedRef(id: 50, name: "Paid Search"), projectCode: "AQ-DM-04", client: arqline, task: NamedRef(id: 5, name: "Ads")),
            TrackableTask(project: NamedRef(id: 51, name: "Paid Search"), projectCode: "AB-DM-04", client: astonBath, task: NamedRef(id: 5, name: "Ads")),
        ]
        func pick(_ title: String, usage: [TaskKey: Double] = [:]) -> Int? {
            MeetingMatcher.suggestion(for: title, tasks: search, entries: [], remembered: [:], usage: usage)?.task.project.id
        }
        // Two clients, no other clue: no guess.
        #expect(pick("Paid Search weekly") == nil)
        #expect(pick("Arqline paid search weekly") == 50)
        #expect(pick("Paid Search weekly", usage: [TaskKey(projectID: 51, taskID: 5): 2]) == 51)
    }

    @Test func sameTitledMeetingsAreLoggedSeparately() {
        let day = LocalDate(year: 2026, month: 10, day: 28)
        let morning = CalendarMeeting(id: "a", title: "Design crit", start: day.date().addingTimeInterval(10 * 3600),
                                      end: day.date().addingTimeInterval(11 * 3600))
        let crit = entry(7, project: 10, task: 1, notes: "Design crit", day: day)
        #expect(MeetingMatcher.isLogged(morning, in: [crit]))
        // Once the 10:00 meeting has claimed that entry, the 15:00 one isn't logged.
        #expect(!MeetingMatcher.isLogged(morning, in: [crit], claimed: [7]))
    }

    @Test func clientNameMustBeWholeWords() {
        #expect(suggest("DAFfodil planting") == nil)
    }

    @Test func nothingForPersonalEvents() {
        #expect(suggest("Lunch") == nil)
        #expect(suggest("Dentist 2:00-3:00") == nil)
    }

    @Test func loggedWhenSameDayEntryHasTheTitle() {
        let start = LocalDate(year: 2026, month: 10, day: 26).date().addingTimeInterval(11 * 3600)
        let meeting = CalendarMeeting(id: "m", title: "Pinstripes weekly sync", start: start, end: start.addingTimeInterval(1800))
        let sameDay = entry(1, project: 10, task: 1, notes: "Pinstripes Weekly Sync", day: meeting.day)
        let otherDay = entry(2, project: 10, task: 1, notes: "Pinstripes weekly sync", day: meeting.day.adding(days: -7))
        #expect(MeetingMatcher.isLogged(meeting, in: [sameDay]))
        #expect(!MeetingMatcher.isLogged(meeting, in: [otherDay]))
        #expect(meeting.hours == 0.5)
    }

    @Test func codesInTitles() {
        #expect(MeetingMatcher.codes(in: "[TB] Digital Products Weekly") == ["TB"])
        #expect(MeetingMatcher.codes(in: "[AB-DM-02] review, also AB-DM-04") == ["AB-DM-02", "AB-DM-04"])
        #expect(MeetingMatcher.codes(in: "Q4-2026 planning 10-11") == [])
    }
}
