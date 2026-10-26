import Foundation
import Observation

/// What's in front of you: the app, its window and, in a browser, the site.
public struct ScreenContext: Hashable, Sendable {
    public var app: String
    public var bundleID: String
    public var title: String
    public var host: String?

    public init(app: String, bundleID: String, title: String, host: String? = nil) {
        self.app = app
        self.bundleID = bundleID
        self.title = title
        self.host = host
    }

    /// Everything a rule or a match can look at, in one string.
    var searchable: String { [app, title, host ?? ""].joined(separator: " ") }
    /// The key learned tasks are filed under: app plus window.
    var learnedKey: String { MeetingMatcher.normalized("\(bundleID)|\(title.isEmpty ? (host ?? "") : title)") }
}

/// An Autotracker rule, as in Toggl: when the app name, window title or
/// website contains any of the keywords, this is the task.
public struct AutotrackRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Comma-separated, any one matches: "Figma, pinstripes".
    public var keywords: String
    public var taskKey: TaskKey

    public init(id: UUID = UUID(), keywords: String, taskKey: TaskKey) {
        self.id = id
        self.keywords = keywords
        self.taskKey = taskKey
    }

    public var terms: [String] {
        keywords.split(separator: ",").map { MeetingMatcher.normalized(String($0)) }.filter { !$0.isEmpty }
    }

    /// The keyword that matched, if any.
    public func match(_ context: ScreenContext) -> String? {
        let text = MeetingMatcher.normalized(context.searchable)
        return terms.first { text.contains($0) }
    }
}

/// Autotracker rules and what's been learned from where you were while a
/// timer ran. Kept in preferences on this Mac.
@MainActor @Observable
public final class ContextMemory {
    public private(set) var rules: [AutotrackRule]
    /// App-and-window → task, from time you tracked there.
    public private(set) var learned: [String: TaskKey]

    @ObservationIgnored private let defaults: UserDefaults
    private static let rulesKey = "autotrack.rules.v1"
    private static let learnedKey = "context.learned.v1"
    /// Enough to cover the windows you live in, without growing forever.
    private static let learnedLimit = 400

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rules = (defaults.data(forKey: Self.rulesKey)).flatMap { try? JSONDecoder().decode([AutotrackRule].self, from: $0) } ?? []
        learned = (defaults.dictionary(forKey: Self.learnedKey) as? [String: String] ?? [:]).compactMapValues(TaskKey.init)
    }

    public func setRules(_ rules: [AutotrackRule]) {
        self.rules = rules
        if let data = try? JSONEncoder().encode(rules) { defaults.set(data, forKey: Self.rulesKey) }
    }

    /// The first rule that matches, like Toggl's top-to-bottom order.
    public func rule(for context: ScreenContext) -> (rule: AutotrackRule, keyword: String)? {
        for rule in rules { if let keyword = rule.match(context) { return (rule, keyword) } }
        return nil
    }

    public func learn(_ context: ScreenContext, key: TaskKey) {
        guard !context.title.isEmpty || context.host != nil else { return }
        learned[context.learnedKey] = key
        if learned.count > Self.learnedLimit { learned.remove(at: learned.startIndex) }
        defaults.set(learned.mapValues(\.description), forKey: Self.learnedKey)
    }
}

public enum ContextMatcher {
    /// Your rules first, then the task you tracked in this exact window,
    /// then the same clues as meetings (codes, project and client names).
    public static func suggestion(
        for context: ScreenContext,
        tasks: [TrackableTask],
        entries: [TimeEntry],
        rules: [AutotrackRule],
        learned: [String: TaskKey],
        usage: [TaskKey: Double]
    ) -> MeetingSuggestion? {
        let byKey = Dictionary(tasks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for rule in rules {
            if let keyword = rule.match(context), let task = byKey[rule.taskKey] {
                return MeetingSuggestion(task: task, reason: .rule(keyword))
            }
        }
        if let key = learned[context.learnedKey], let task = byKey[key] {
            return MeetingSuggestion(task: task, reason: .trackedHere(context.app))
        }
        let clues = [context.title, context.host ?? ""].joined(separator: " ")
        return MeetingMatcher.suggestion(for: clues, tasks: tasks, entries: entries, remembered: [:], usage: usage)
    }
}

extension TimeTracker {
    /// The task what's on screen points to, if anything does.
    public func suggestion(for context: ScreenContext) -> MeetingSuggestion? {
        ContextMatcher.suggestion(
            for: context, tasks: tasks, entries: entries,
            rules: contextMemory.rules, learned: contextMemory.learned, usage: usage
        )
    }
}
