import Foundation
import Testing
@testable import HarvestKit

struct TrackingTests {
    let figma = ScreenContext(app: "Figma", bundleID: "com.figma.Desktop", title: "Pinstripes – Homepage v3")
    let ads = ScreenContext(app: "Google Chrome", bundleID: "com.google.Chrome", title: "Campaigns", host: "ads.google.com")
    let pinstripes = TrackableTask(project: NamedRef(id: 10, name: "Creative Support"), projectCode: "PS-CS-03",
                                   client: NamedRef(id: 1, name: "Pinstripes"), task: NamedRef(id: 1, name: "Design"))
    let arqline = TrackableTask(project: NamedRef(id: 20, name: "Paid Search"), projectCode: "AQ-DM-04",
                                client: NamedRef(id: 2, name: "Arqline"), task: NamedRef(id: 2, name: "Ads"))

    @Test func ruleMatchesAnyKeywordInAppTitleOrSite() {
        let rule = AutotrackRule(keywords: "ads.google, nothing", taskKey: arqline.key)
        #expect(rule.match(ads) == "ads.google")
        #expect(rule.match(figma) == nil)
        #expect(AutotrackRule(keywords: "FIGMA", taskKey: pinstripes.key).match(figma) == "figma")
        #expect(AutotrackRule(keywords: " , ", taskKey: pinstripes.key).match(figma) == nil)
    }

    @Test func contextSuggestionPrefersRulesThenWhereYouTrackedThenNames() {
        func suggest(rules: [AutotrackRule] = [], learned: [String: TaskKey] = [:], _ context: ScreenContext) -> MeetingSuggestion? {
            ContextMatcher.suggestion(for: context, tasks: [pinstripes, arqline], entries: [], rules: rules, learned: learned, usage: [:])
        }
        // "Pinstripes" in the title names the client, but with no history
        // and no meetings task there's nothing confident to say.
        #expect(suggest(figma) == nil)
        let rule = AutotrackRule(keywords: "figma", taskKey: arqline.key)
        #expect(suggest(rules: [rule], figma)?.reason == .rule("figma"))
        #expect(suggest(learned: [figma.learnedKey: arqline.key], figma)?.reason == .trackedHere("Figma"))
        #expect(suggest(rules: [rule], learned: [figma.learnedKey: pinstripes.key], figma)?.task.key == arqline.key)
    }

    @Test func untrackedSpansGroupIntoStretches() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func span(_ from: Double, _ to: Double, tracked: Bool = false, title: String = "Doc") -> ActivitySpan {
            ActivitySpan(app: "Figma", bundleID: "f", title: title, start: t0.addingTimeInterval(from * 60),
                         end: t0.addingTimeInterval(to * 60), trackedKey: tracked ? pinstripes.key : nil)
        }
        let spans = [
            span(0, 4), span(5, 9, title: "Other"),   // 8 min, a 1-minute gap: one stretch
            span(9, 30, tracked: true),               // a timer was running
            span(31, 33),                             // 2 min alone: too short
            span(40, 50), span(52, 56),               // 14 min
        ]
        let stretches = Timeline.untrackedStretches(spans)
        #expect(stretches.map { Int($0.seconds / 60) } == [8, 14])
        #expect(stretches[0].topLabels.first == "Figma · Doc")
        #expect(stretches[0].asMeeting.isActivity)
        #expect(stretches[0].asMeeting.context?.title == "Doc")
    }

    @Test @MainActor func timelineStoreJoinsAndDropsShortSpans() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TimelineStore(folder: folder)
        let t0 = Date()
        let span = ActivitySpan(app: "Figma", bundleID: "f", title: "Doc", start: t0, end: t0.addingTimeInterval(60))
        store.append(span)
        // The same window again right after carries the span on.
        store.append(ActivitySpan(app: "Figma", bundleID: "f", title: "Doc", start: t0.addingTimeInterval(65), end: t0.addingTimeInterval(120)))
        // Ten seconds or less isn't kept.
        store.append(ActivitySpan(app: "Mail", bundleID: "m", title: "", start: t0.addingTimeInterval(121), end: t0.addingTimeInterval(130)))
        let reloaded = TimelineStore(folder: folder).spans(on: LocalDate(t0))
        #expect(reloaded.count == 1)
        #expect(reloaded.first?.end == t0.addingTimeInterval(120))
        try? FileManager.default.removeItem(at: folder)
    }

    @Test @MainActor func continueStartsTheLastEntryAgainThenStops() async {
        let defaults = UserDefaults(suiteName: "TrackingTests")!
        defaults.removePersistentDomain(forName: "TrackingTests")
        let tracker = TimeTracker(service: DemoHarvestService(), accountName: "Test",
                                  favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
                                  meetingMemory: MeetingMemory(defaults: defaults),
                                  contextMemory: ContextMemory(defaults: defaults), isDemo: true)
        await tracker.refresh(force: true)
        #expect(tracker.running != nil) // the demo has a timer going
        await tracker.continueOrStop()
        #expect(tracker.running == nil)
        let stopped = tracker.pausedEntry?.key
        await tracker.continueOrStop()
        #expect(tracker.running?.key == stopped)
    }
}
