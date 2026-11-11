import Foundation
import Testing
@testable import HarvestKit

struct GapFinderTests {
    let day = LocalDate(year: 2026, month: 11, day: 10) // a Tuesday

    private func entry(_ id: Int, _ from: String?, _ to: String?, running: Bool = false, startedAt: Date? = nil, hours: Double = 1, notes: String? = "x") -> TimeEntry {
        TimeEntry(id: id, spentDate: day, project: NamedRef(id: 1, name: "Website"), task: NamedRef(id: 1, name: "Design"),
                  client: nil, hours: hours, hoursWithoutTimer: running ? 0 : nil, notes: notes, isRunning: running,
                  timerStartedAt: startedAt, startedTime: from, endedTime: to)
    }

    @Test func findsGapsOfTwentyMinutesOrMore() {
        // 9:30–10:30, 10:40–12:00, 1:05–6:00: a 30-minute start, a 10-minute
        // break (too short) and 12:00–1:05.
        let gaps = GapFinder.gaps(day: day, covered: [570..<630, 640..<720, 785..<1080])
        #expect(gaps.map { [$0.start, $0.end] } == [[540, 570], [720, 785]])
    }

    @Test func overlappingAndOutOfHoursEntriesMerge() {
        // Unsorted, overlapping, and one running from 8:00 into the day.
        let gaps = GapFinder.gaps(day: day, covered: [600..<700, 480..<610, 650..<690, 1000..<1200])
        #expect(gaps.map { [$0.start, $0.end] } == [[700, 1000]])
    }

    @Test func todayStopsAtNow() {
        let covered = [540..<600]
        #expect(GapFinder.gaps(day: day, covered: covered, until: 615).isEmpty) // only 15 minutes so far
        #expect(GapFinder.gaps(day: day, covered: covered, until: 700).map(\.end) == [700])
        #expect(GapFinder.gaps(day: day, covered: [], until: 8 * 60).isEmpty)
    }

    @Test func customWorkingHoursAndMinimum() {
        let gaps = GapFinder.gaps(day: day, covered: [600..<660], workday: 8 * 60..<16 * 60, minimum: 30)
        #expect(gaps.map { [$0.start, $0.end] } == [[480, 600], [660, 960]])
    }

    @Test func entriesGiveTheirClockSpans() {
        let now = day.date().addingTimeInterval(15 * 3600) // 3:00pm
        let entries = [
            entry(1, "9:00am", "12:30pm"),
            // Running since 1:30pm: covers up to now.
            entry(2, "1:30pm", nil, running: true, startedAt: now.addingTimeInterval(-90 * 60)),
            // No times (a duration entry): can't be placed, so it's ignored.
            entry(3, nil, nil),
        ]
        #expect(GapFinder.span(of: entries[1], at: now) == 810..<900)
        #expect(GapFinder.span(of: entries[2], at: now) == nil)
        let gaps = GapFinder.gaps(day: day, entries: entries, until: 16 * 60, now: now)
        #expect(gaps.map(\.label) == ["12:30–1:30", "3:00–4:00"])
        #expect(gaps.first?.fullLabel == "12:30pm–1:30pm")
        #expect(gaps.first?.hours == 1)
    }

    @Test func meetingsOverlappingAGap() {
        let gap = TimeGap(day: day, start: 13 * 60, end: 14 * 60 + 30)
        let at = { (h: Double) in self.day.date().addingTimeInterval(h * 3600) }
        let sync = CalendarMeeting(id: "a", title: "Acme sync", start: at(13), end: at(14))
        let brief = CalendarMeeting(id: "b", title: "Brief", start: at(14.25), end: at(15))        // 15 min in
        let edge = CalendarMeeting(id: "c", title: "Edge", start: at(12.5), end: at(13.1))          // 6 min in
        let activity = CalendarMeeting(id: "d", title: "Figma", start: at(13), end: at(14), isActivity: true)
        #expect(GapFinder.meetings(overlapping: gap, in: [brief, edge, sync, activity]).map(\.id) == ["a", "b"])
    }

    @Test func topActivityIsTheMostUsedUntrackedApp() {
        let gap = TimeGap(day: day, start: 13 * 60, end: 15 * 60)
        let at = { (h: Double) in self.day.date().addingTimeInterval(h * 3600) }
        let spans = [
            ActivitySpan(app: "Figma", bundleID: "figma", title: "Website – Nav", start: at(13), end: at(13.25)),
            ActivitySpan(app: "Figma", bundleID: "figma", title: "Website – Footer", start: at(13.5), end: at(13.9)),
            ActivitySpan(app: "Slack", bundleID: "slack", title: "#general", start: at(13.25), end: at(13.5)),
            // Mostly before the gap: only its last 3 minutes count.
            ActivitySpan(app: "Mail", bundleID: "mail", title: "Inbox", start: at(11), end: at(13.05)),
            // Already tracked: doesn't count.
            ActivitySpan(app: "Xcode", bundleID: "xcode", title: "app", start: at(14), end: at(15), trackedKey: TaskKey(projectID: 1, taskID: 1)),
        ]
        let top = GapFinder.topActivity(in: gap, spans: spans)
        #expect(top?.context.app == "Figma")
        #expect(top?.context.title == "Website – Footer") // its longest window
        #expect(abs((top?.seconds ?? 0) - 39 * 60) < 1) // 15 + 24 minutes
        // Under five minutes in total isn't enough to go on.
        #expect(GapFinder.topActivity(in: gap, spans: [spans[3]]) == nil)
    }
}

struct RetiredBucketTests {
    @Test func matchesTheRetiredBuckets() {
        #expect(RetiredBuckets.isRetired(project: "Digital Products", task: "Design"))
        #expect(RetiredBuckets.isRetired(project: "[TB-DP] Digital Products", task: "Design"))
        #expect(RetiredBuckets.isRetired(project: "Digital Products (Generic)", task: "Design"))
        #expect(RetiredBuckets.isRetired(project: "Internal", task: "Business Dev"))
        #expect(RetiredBuckets.isRetired(project: "Business Dev (Legacy)", task: "Strategy"))
        #expect(RetiredBuckets.isRetired(project: "business  DEV", task: "Strategy"))
    }

    @Test func leavesSpecificBucketsAlone() {
        #expect(!RetiredBuckets.isRetired(project: "Digital Products – Acme", task: "Design"))
        #expect(!RetiredBuckets.isRetired(project: "Business Development", task: "Strategy"))
        #expect(!RetiredBuckets.isRetired(project: "Website Redesign", task: "Design"))
    }
}

struct WeekReviewTests {
    let monday = LocalDate(year: 2026, month: 11, day: 9)
    var friday: LocalDate { monday.adding(days: 4) }
    var fridayAt4: Date { friday.date().addingTimeInterval(16 * 3600) }

    @Test func findsEachKindOfItemInOrder() {
        let entries = DemoHarvestService.reviewWeekEntries(monday: monday, now: fridayAt4, firstID: 1)
        let items = WeekReview.items(today: friday, now: fridayAt4, firstWeekday: 2, usualDay: 8 * 3600,
                                     entries: entries, tracksStartAndEnd: true)
        #expect(items.map(\.id) == [
            "timer-11",                       // Thursday's timer, still running
            "retired-4",                      // Monday: Digital Products
            "short-\(monday.adding(days: 1))", // Tuesday: 5:30 of 8:00
            "gap-\(monday.adding(days: 1))@780-840",  // 1:00–2:00
            "gap-\(monday.adding(days: 1))@930-1080", // 3:30–6:00
            "notes-7",                        // Tuesday's QA entry
            "empty-\(monday.adding(days: 2))", // Wednesday
            "retired-10",                     // Thursday: Business Dev
            "notes-14",                       // Friday, no notes
        ])
        if case .shortDay(_, let logged, let usual) = items[2] {
            #expect(logged == 5.5 * 3600)
            #expect(usual == 8 * 3600)
        } else {
            Issue.record("expected a short day")
        }
    }

    @Test func allSetWhenEverythingIsIn() {
        let entries = (0..<5).flatMap { offset -> [TimeEntry] in
            let day = monday.adding(days: offset)
            return [TimeEntry(id: offset, spentDate: day, project: NamedRef(id: 1, name: "Website"), task: NamedRef(id: 1, name: "Design"),
                              client: nil, hours: 9, notes: "Work", startedTime: "9:00am", endedTime: "6:00pm")]
        }
        #expect(WeekReview.items(today: friday, now: fridayAt4, firstWeekday: 2, usualDay: 8 * 3600,
                                 entries: entries, tracksStartAndEnd: true).isEmpty)
    }

    @Test func ignoredGapsStayHidden() {
        let entries = DemoHarvestService.reviewWeekEntries(monday: monday, now: fridayAt4, firstID: 1)
        let ignored: Set<String> = ["\(monday.adding(days: 1))@780-840"]
        let items = WeekReview.items(today: friday, now: fridayAt4, firstWeekday: 2, usualDay: 8 * 3600,
                                     entries: entries, tracksStartAndEnd: true, ignoredGaps: ignored)
        #expect(items.filter { if case .gap = $0 { true } else { false } }.count == 1)
    }

    @Test func midweekTodayIsntShortOrEmptyYet() {
        let wednesday = monday.adding(days: 2)
        let noon = wednesday.date().addingTimeInterval(12 * 3600)
        let entries = [TimeEntry(id: 1, spentDate: monday, project: NamedRef(id: 1, name: "Website"), task: NamedRef(id: 1, name: "Design"),
                                 client: nil, hours: 8, notes: "Work")]
        let items = WeekReview.items(today: wednesday, now: noon, firstWeekday: 2, usualDay: 8 * 3600,
                                     entries: entries, tracksStartAndEnd: false)
        // Tuesday is empty; Wednesday is still under way. No gaps: a duration account.
        #expect(items.map(\.id) == ["empty-\(monday.adding(days: 1))"])
    }

    @Test func durationAccountsGetDayTotalsNotGaps() {
        let entries = DemoHarvestService.reviewWeekEntries(monday: monday, now: fridayAt4, firstID: 1)
        let items = WeekReview.items(today: friday, now: fridayAt4, firstWeekday: 2, usualDay: 8 * 3600,
                                     entries: entries, tracksStartAndEnd: false)
        #expect(!items.contains { if case .gap = $0 { true } else { false } })
        #expect(items.contains { $0.id == "short-\(monday.adding(days: 1))" })
    }

    @Test func lockedEntriesArentFlagged() {
        let entry = TimeEntry(id: 1, spentDate: monday, project: NamedRef(id: 1, name: "Digital Products"), task: NamedRef(id: 1, name: "Design"),
                              client: nil, hours: 8, notes: nil, isLocked: true, isClosed: true)
        let items = WeekReview.items(today: monday, now: monday.date().addingTimeInterval(17 * 3600), firstWeekday: 2,
                                     usualDay: 8 * 3600, entries: [entry], tracksStartAndEnd: false)
        #expect(items.isEmpty)
    }
}

struct FridayReminderTests {
    /// 2026-11-13 is a Friday; Central is UTC−6 in November.
    private func utc(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func dueFridayAfterFourCentral() {
        #expect(WeekReview.reminderDue(now: utc(13, 22, 5), reminderMinutes: 16 * 60, lastReminded: nil) == "2026-11-13")
        #expect(WeekReview.reminderDue(now: utc(13, 21, 59), reminderMinutes: 16 * 60, lastReminded: nil) == nil)
        // Already reminded today.
        #expect(WeekReview.reminderDue(now: utc(13, 22, 30), reminderMinutes: 16 * 60, lastReminded: "2026-11-13") == nil)
        // After the 6 PM close.
        #expect(WeekReview.reminderDue(now: utc(14, 0, 5), reminderMinutes: 16 * 60, lastReminded: nil) == nil)
        // Thursday at 4 PM Central.
        #expect(WeekReview.reminderDue(now: utc(12, 22, 5), reminderMinutes: 16 * 60, lastReminded: nil) == nil)
    }

    @Test func centralTimesConvert() {
        // Friday 6 PM Central is midnight UTC.
        #expect(WeekReview.deadline(containing: LocalDate(year: 2026, month: 11, day: 11), firstWeekday: 2) == utc(14, 0))
        #expect(WeekReview.centralMinutes(of: utc(13, 22, 0)) == 16 * 60)
        #expect(WeekReview.date(centralMinutes: 16 * 60, on: utc(13, 18)) == utc(13, 22))
    }
}
