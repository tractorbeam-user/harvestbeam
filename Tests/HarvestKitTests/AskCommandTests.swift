import Foundation
import Testing
@testable import HarvestKit

struct AskCommandParsingTests {
    @Test func readsMoves() {
        #expect(AskCommand.parse("move 20 min from Managerial Tasks to Dallas Art Fair")
            == .move(hours: 20.0 / 60, from: .named("managerial tasks"), to: "dallas art fair"))
        #expect(AskCommand.parse("move 20m from admin to website")
            == .move(hours: 20.0 / 60, from: .named("admin"), to: "website"))
        #expect(AskCommand.parse("Move 1:15 from admin into the website")
            == .move(hours: 1.25, from: .named("admin"), to: "website"))
        #expect(AskCommand.parse("take 15 from admin give to website")
            == .move(hours: 0.25, from: .named("admin"), to: "website"))
        #expect(AskCommand.parse("take 15 min off admin and give it to website")
            == .move(hours: 0.25, from: .named("admin"), to: "website"))
        #expect(AskCommand.parse("move half an hour from the last entry to website")
            == .move(hours: 0.5, from: .last, to: "website"))
        // The first "to" splits, so names can have one too.
        #expect(AskCommand.parse("move 10m from admin to back to school")
            == .move(hours: 10.0 / 60, from: .named("admin"), to: "back to school"))
    }

    @Test func readsHours() {
        #expect(AskCommand.parse("change last entry to 45m") == .setHours(.last, hours: 0.75))
        #expect(AskCommand.parse("make Dallas Art Fair 1:30") == .setHours(.named("dallas art fair"), hours: 1.5))
        #expect(AskCommand.parse("set website to 2 hours") == .setHours(.named("website"), hours: 2))
        #expect(AskCommand.parse("make it 45 minutes") == .setHours(.last, hours: 0.75))
        // Bare numbers: small ones are hours, big ones minutes.
        #expect(AskCommand.parse("make website 2") == .setHours(.named("website"), hours: 2))
        #expect(AskCommand.parse("make website 45") == .setHours(.named("website"), hours: 0.75))
    }

    @Test func readsNotesAndPause() {
        #expect(AskCommand.parse("note: client feedback round 2") == .note("client feedback round 2"))
        #expect(AskCommand.parse("Notes:Kickoff prep") == .note("Kickoff prep"))
        #expect(AskCommand.parse("stop") == .pause)
        #expect(AskCommand.parse("Pause") == .pause)
        #expect(AskCommand.parse("stop the timer") == .pause)
    }

    @Test func leavesSearchesAndPlansAlone() {
        for text in ["website", "10 min on website", "move", "note:", "make website", "change management",
                     "stopwatch", "moving company", "take a break", "set design 2025 project"] {
            #expect(AskCommand.parse(text) == nil, "\(text)")
        }
    }

    @Test func readsAmounts() {
        #expect(AskCommand.amount("20 min", bareMinutesFrom: 5) == 20.0 / 60)
        #expect(AskCommand.amount("1h30m", bareMinutesFrom: 5) == 1.5)
        #expect(AskCommand.amount("an hour", bareMinutesFrom: 5) == 1)
        #expect(AskCommand.amount("3", bareMinutesFrom: 5) == 3)
        #expect(AskCommand.amount("15", bareMinutesFrom: 5) == 0.25)
        #expect(AskCommand.amount("lots", bareMinutesFrom: 5) == nil)
        #expect(AskCommand.amount("0", bareMinutesFrom: 5) == nil)
    }
}

struct AskCommandResolverTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var today: LocalDate { LocalDate(now) }

    let managerial = TrackableTask(project: NamedRef(id: 1, name: "[TB-DP-01] Internal"), client: NamedRef(id: 9, name: "Tractorbeam"),
                                   task: NamedRef(id: 10, name: "Managerial Tasks"))
    let fairDesign = TrackableTask(project: NamedRef(id: 2, name: "Dallas Art Fair"), client: NamedRef(id: 8, name: "DAF"),
                                   task: NamedRef(id: 11, name: "Design"))
    let fairMeetings = TrackableTask(project: NamedRef(id: 2, name: "Dallas Art Fair"), client: NamedRef(id: 8, name: "DAF"),
                                     task: NamedRef(id: 12, name: "Meetings"))
    let website = TrackableTask(project: NamedRef(id: 3, name: "Website Redesign"), client: NamedRef(id: 9, name: "Tractorbeam"),
                                task: NamedRef(id: 11, name: "Design"))

    func entry(_ id: Int, _ task: TrackableTask, hours: Double, running: Bool = false, minutesAgo: Double = 60,
               locked: Bool = false, notes: String? = nil) -> TimeEntry {
        let created = now.addingTimeInterval(-minutesAgo * 60)
        return TimeEntry(id: id, spentDate: today, project: task.project, task: task.task, client: task.client,
                         hours: hours, hoursWithoutTimer: running ? hours : nil, notes: notes, isRunning: running,
                         timerStartedAt: running ? now : nil, createdAt: created, updatedAt: created,
                         isLocked: locked ? true : nil)
    }

    func resolver(_ entries: [TimeEntry], usage: [TaskKey: Double] = [:]) -> AskCommandResolver {
        let all = [managerial, fairDesign, fairMeetings, website]
        let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
        return AskCommandResolver(today: entries, tasks: Ranking.SearchIndex(tasks: all), usage: usage,
                                  taskFor: { byKey[$0.key]! }, now: now)
    }

    @Test func previewsAMove() {
        let r = resolver([entry(1, managerial, hours: 0.7833), entry(2, fairDesign, hours: 1)])
        let preview = r.preview(.move(hours: 20.0 / 60, from: .named("managerial tasks"), to: "dallas art fair"))
        guard case .move(let seconds, let from, let to) = preview.plan else { Issue.record("\(preview.plan)"); return }
        #expect(seconds == 1200)
        #expect(from.id == 1)
        // Dallas Art Fair has two tasks; the one tracked today wins.
        #expect(to == fairDesign)
        #expect(preview.title == "Move 0:20 from Managerial Tasks to Dallas Art Fair · leaves 0:27")
    }

    @Test func prefersTheRunningEntryThenTheLatest() throws {
        let older = entry(1, managerial, hours: 1, minutesAgo: 200)
        let newer = entry(2, managerial, hours: 1, minutesAgo: 30)
        let running = entry(3, managerial, hours: 0.5, running: true, minutesAgo: 100)
        #expect(try resolver([older, newer]).entry(.named("managerial")).get().id == 2)
        #expect(try resolver([older, running, newer]).entry(.named("managerial")).get().id == 3)
        #expect(try resolver([older, running, newer]).entry(.last).get().id == 3)
        #expect(try resolver([older, newer]).entry(.last).get().id == 2)
    }

    @Test func saysWhenThereIsNotEnoughTime() {
        let r = resolver([entry(1, managerial, hours: 0.25)])
        let plan = r.resolve(.move(hours: 0.5, from: .named("managerial"), to: "website"))
        #expect(plan == .problem("Internal only has 0:15 today"))
        // A stopped entry can give all of its time.
        #expect(r.resolve(.move(hours: 0.25, from: .named("managerial"), to: "website")).isReady)
    }

    @Test func refusesLockedEntries() {
        let r = resolver([entry(1, managerial, hours: 2, locked: true)])
        #expect(!r.resolve(.move(hours: 0.5, from: .named("managerial"), to: "website")).isReady)
        #expect(!r.resolve(.setHours(.last, hours: 1)).isReady)
        #expect(!r.resolve(.note("hi")).isReady)
        let preview = r.preview(.setHours(.last, hours: 1))
        #expect(preview.title.hasPrefix("Can't change the time: "))
        #expect(preview.title.contains("locked"))
    }

    @Test func listsChoicesWhenANameIsAmbiguous() {
        // Nothing today on the fair, and no history to break the tie.
        let r = resolver([entry(1, managerial, hours: 2)])
        let plan = r.resolve(.move(hours: 0.5, from: .last, to: "dallas"))
        guard case .problem(_, let choices) = plan else { Issue.record("\(plan)"); return }
        #expect(choices == ["Dallas Art Fair · Design", "Dallas Art Fair · Meetings"])
        // History settles it.
        let used = resolver([entry(1, managerial, hours: 2)], usage: [fairMeetings.key: 2])
        #expect(used.resolve(.move(hours: 0.5, from: .last, to: "dallas")) == .move(seconds: 1800, from: entry(1, managerial, hours: 2), to: fairMeetings))
        // So does naming the task.
        #expect(r.task(named: "dallas art fair meetings").map(\.key) == .success(fairMeetings.key))
    }

    @Test func ambiguousSourceAmongTodaysEntries() throws {
        let r = resolver([entry(1, fairDesign, hours: 1), entry(2, fairMeetings, hours: 1)])
        guard case .failure(let problem) = r.entry(.named("dallas")), case .problem(_, let choices) = problem.plan else {
            Issue.record("expected ambiguity"); return
        }
        #expect(choices.count == 2)
        #expect(try r.entry(.named("design")).get().id == 1)
    }

    @Test func setsHoursAndNotes() {
        let running = entry(3, website, hours: 0.5, running: true, notes: "old")
        let r = resolver([entry(1, managerial, hours: 1), running])
        #expect(r.resolve(.setHours(.named("website"), hours: 0.75)) == .setHours(running, hours: 0.75))
        let preview = r.preview(.setHours(.last, hours: 0.75))
        #expect(preview.title == "Set Website Redesign to 0:45 · was 0:30")
        #expect(preview.detail?.contains("stops the timer") == true)
        #expect(r.resolve(.note("client feedback round 2")) == .note(running, "client feedback round 2"))
        #expect(r.preview(.note("x")).detail?.contains("replaces “old”") == true)
        #expect(!r.resolve(.setHours(.last, hours: 30)).isReady)
    }

    @Test func pausesOnlyWhatsRunning() {
        let running = entry(3, website, hours: 0.5, running: true)
        #expect(resolver([running]).resolve(.pause) == .pause(running))
        #expect(!resolver([entry(1, managerial, hours: 1)]).resolve(.pause).isReady)
        #expect(!resolver([]).resolve(.note("hi")).isReady)
    }

    @Test func refusesTheSameTaskAndUnknownNames() {
        let r = resolver([entry(1, managerial, hours: 1)])
        #expect(r.resolve(.move(hours: 0.25, from: .last, to: "managerial tasks")) == .problem("That's the same task"))
        #expect(r.resolve(.move(hours: 0.25, from: .named("zebra"), to: "website")) == .problem("Nothing tracked today matches “zebra”"))
        #expect(r.resolve(.move(hours: 0.25, from: .last, to: "zebra")) == .problem("No task matches “zebra”"))
    }
}

@MainActor
struct AskCommandTrackerTests {
    @Test func appliesAMoveThroughTheTracker() async throws {
        let defaults = UserDefaults(suiteName: "AskCommandTests")!
        defaults.removePersistentDomain(forName: "AskCommandTests")
        let tracker = TimeTracker(service: DemoHarvestService(), accountName: "Test",
                                  favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
                                  meetingMemory: MeetingMemory(defaults: defaults), isDemo: true)
        await tracker.refresh(force: true)
        let source = try #require(tracker.todayEntries.first { !$0.isRunning && $0.elapsed() > 1800 })
        let name = tracker.task(for: source).task.name + " " + tracker.task(for: source).projectNameParts.name
        let target = try #require(tracker.tasks.first { $0.key != source.key && !tracker.todayEntries.map(\.key).contains($0.key) })
        let preview = try #require(tracker.askCommand("move 10 min from \(name) to \(target.projectNameParts.name) \(target.task.name)"))
        #expect(preview.plan.isReady, "\(preview.title)")
        #expect(await tracker.perform(preview.plan))
        #expect(tracker.todayEntries.contains { $0.key == target.key && abs($0.elapsed() - 600) < 60 })
    }
}
