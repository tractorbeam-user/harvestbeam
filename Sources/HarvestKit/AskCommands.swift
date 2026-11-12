import Foundation

/// Something typed into the ask box that changes today's time rather than
/// searching: "move 20 min from Admin to Website", "make Website 1:30",
/// "note: client feedback", "stop". Read with fixed rules, no model.
public enum AskCommand: Equatable, Sendable {
    /// Which of today's entries a command is about.
    public enum Target: Equatable, Sendable {
        /// The running entry, or else the latest one: "last entry", "it".
        case last
        /// Matched by name against today's entries.
        case named(String)
    }

    case move(hours: Double, from: Target, to: String)
    case setHours(Target, hours: Double)
    case note(String)
    case pause

    /// The command in `text`, or nil when it's a search (or a "10 min on X"
    /// entry, which the day planner reads).
    public static func parse(_ text: String) -> AskCommand? {
        // Dictation ends sentences with a period: "Make Website 45 minutes."
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, ".!".contains(last) { trimmed.removeLast() }
        let lower = trimmed.lowercased()
        guard !lower.isEmpty else { return nil }

        // "stop", "pause", "stop the timer"
        if lower.wholeMatch(of: /(stop|pause)( (the )?(timer|it|tracking))?[.!]?/) != nil { return .pause }

        // "note: client feedback round 2", "notes: …"
        if let match = trimmed.wholeMatch(of: /(?i)notes?\s*:\s*(.*)/) {
            let note = String(match.1).trimmingCharacters(in: .whitespaces)
            return note.isEmpty ? nil : .note(note)
        }

        // "move 20 min from X to Y"
        if let match = lower.wholeMatch(of: /move\s+(.+?)\s+from\s+(.+?)\s+(?:to|into|onto)\s+(.+)/),
           let hours = amount(String(match.1), bareMinutesFrom: 5) {
            return .move(hours: hours, from: target(String(match.2)), to: clean(String(match.3)))
        }
        // "take 15 from X give to Y", "take 15 min off X and give it to Y"
        if let match = lower.wholeMatch(of: /take\s+(.+?)\s+(?:from|off(?: of)?)\s+(.+?)\s*,?\s+(?:and\s+)?(?:give|put|add)\s+(?:it\s+)?(?:to|on)\s+(.+)/),
           let hours = amount(String(match.1), bareMinutesFrom: 5) {
            return .move(hours: hours, from: target(String(match.2)), to: clean(String(match.3)))
        }

        // "change last entry to 45m", "set Website to 1:30", "make Website 1:30"
        if let match = lower.wholeMatch(of: /(?:change|set|make)\s+(.+)/) {
            let rest = String(match.1)
            let words = rest.split(separator: " ").map(String.init)
            // The amount is the last word to three: "45m", "45 min", "half an hour".
            for count in [3, 2, 1] where words.count > count {
                let amountText = words.suffix(count).joined(separator: " ")
                guard let hours = amount(amountText, bareMinutesFrom: 13) else { continue }
                var name = words.dropLast(count)
                if name.last == "to" { name = name.dropLast() }
                guard !name.isEmpty else { continue }
                return .setHours(target(name.joined(separator: " ")), hours: hours)
            }
        }
        return nil
    }

    /// Hours in "20 min", "20m", "1:30", "1h", "1.5 hours", "an hour", "half
    /// an hour". A bare whole number is minutes from `bareMinutesFrom` up
    /// ("take 15 from X"), hours below it ("make X 2").
    static func amount(_ text: String, bareMinutesFrom threshold: Int) -> Double? {
        var s = text.trimmingCharacters(in: .whitespaces)
        switch s {
        case "an hour", "one hour", "1 hour": return 1
        case "half an hour", "half hour": return 0.5
        case "a quarter hour", "quarter hour", "quarter of an hour": return 0.25
        default: break
        }
        if let whole = Int(s) {
            guard whole > 0 else { return nil }
            return whole >= threshold ? Double(whole) / 60 : Double(whole)
        }
        // Spelled-out units the hours parser doesn't take.
        s = s.replacing(/\s*(minutes|minute)$/, with: "m")
        s = s.replacing(/\s*(hours|hour)$/, with: "h")
        guard s.contains(where: \.isNumber), let hours = TimeFormat.parseHours(s), hours > 0 else { return nil }
        return hours
    }

    private static func target(_ text: String) -> Target {
        let name = clean(text)
        let last: Set<String> = [
            "last", "last entry", "the last entry", "last one", "the last one", "my last entry",
            "it", "this", "that", "current", "the current entry", "running", "the running entry", "timer", "the timer",
        ]
        return last.contains(name) ? .last : .named(name)
    }

    private static func clean(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        if s.hasPrefix("the ") { s = String(s.dropFirst(4)) }
        return s
    }
}

/// What a command will do once it's been matched to today's entries, or why
/// it can't.
public enum AskCommandPlan: Equatable, Sendable {
    case move(seconds: TimeInterval, from: TimeEntry, to: TrackableTask)
    case setHours(TimeEntry, hours: Double)
    case note(TimeEntry, String)
    case pause(TimeEntry)
    /// It can't work; `choices` lists the tasks a name could mean.
    case problem(String, choices: [String] = [])

    public var isReady: Bool {
        if case .problem = self { return false }
        return true
    }
}

/// A command and its plan, worded for the ask box's preview row.
public struct AskCommandPreview: Equatable, Sendable {
    public let command: AskCommand
    public let plan: AskCommandPlan
    /// "Move 0:20 from Admin to Website Redesign · leaves 0:27"
    public let title: String
    /// The tasks in full, or the problem's choices.
    public let detail: String?
}

/// Matches a command to today's entries and the account's tasks. Pure, so
/// it's easy to test; `TimeTracker.askCommand(_:)` feeds it.
public struct AskCommandResolver {
    public let today: [TimeEntry]
    public let tasks: Ranking.SearchIndex
    public let usage: [TaskKey: Double]
    public let taskFor: (TimeEntry) -> TrackableTask
    public let unavailable: (TaskKey) -> String?
    public let now: Date

    public init(
        today: [TimeEntry], tasks: Ranking.SearchIndex, usage: [TaskKey: Double] = [:],
        taskFor: @escaping (TimeEntry) -> TrackableTask, unavailable: @escaping (TaskKey) -> String? = { _ in nil },
        now: Date = .now
    ) {
        self.today = today
        self.tasks = tasks
        self.usage = usage
        self.taskFor = taskFor
        self.unavailable = unavailable
        self.now = now
    }

    private var running: TimeEntry? { today.first(where: \.isRunning) }

    /// Why a name couldn't be matched, as the plan to show.
    struct Problem: Error, Equatable {
        let plan: AskCommandPlan
        init(_ plan: AskCommandPlan) { self.plan = plan }
    }

    public func preview(_ command: AskCommand) -> AskCommandPreview {
        let plan = resolve(command)
        let (title, detail) = words(for: command, plan: plan)
        return AskCommandPreview(command: command, plan: plan, title: title, detail: detail)
    }

    public func resolve(_ command: AskCommand) -> AskCommandPlan {
        switch command {
        case .pause:
            guard let running else { return .problem("no timer is running") }
            return .pause(running)

        case .note(let text):
            switch entry(.last) {
            case .failure(let problem): return problem.plan
            case .success(let entry):
                if let lock = entry.lock { return .problem("\(label(taskFor(entry))) is \(lock.title.lowercased()), so its notes can't change") }
                return .note(entry, text)
            }

        case .setHours(let target, let hours):
            switch entry(target) {
            case .failure(let problem): return problem.plan
            case .success(let entry):
                if let lock = entry.lock { return .problem("\(label(taskFor(entry))) is \(lock.title.lowercased()), so it can't change") }
                guard hours <= 24 else { return .problem("That's more than a day") }
                return .setHours(entry, hours: hours)
            }

        case .move(let hours, let from, let to):
            let source: TimeEntry
            switch entry(from) {
            case .failure(let problem): return problem.plan
            case .success(let found): source = found
            }
            let destination: TrackableTask
            switch task(named: to) {
            case .failure(let problem): return problem.plan
            case .success(let found): destination = found
            }
            let from = label(taskFor(source))
            if let lock = source.lock { return .problem("\(from) is \(lock.title.lowercased()), so its time can't move") }
            if destination.key == source.key { return .problem("That's the same task") }
            if let reason = unavailable(destination.key) { return .problem("Can't add time to \(label(destination)). \(reason)") }
            // The same limits as `TimeTracker.moveTime`.
            let moving = (hours * 60).rounded() / 60
            let had = source.elapsed(at: now) / 3600
            guard moving >= 1.0 / 60 else { return .problem("Move at least a minute") }
            guard moving <= had - 1.0 / 60 || (!source.isRunning && moving <= had) else {
                return .problem("\(from) only has \(TimeFormat.hoursMinutes(had * 3600)) today")
            }
            return .move(seconds: moving * 3600, from: source, to: destination)
        }
    }

    // MARK: Matching names

    /// One of today's entries: the running one, else the latest, among the
    /// entries of the task the name matches.
    func entry(_ target: AskCommand.Target) -> Result<TimeEntry, Problem> {
        guard !today.isEmpty else { return .failure(Problem(.problem("Nothing tracked today yet"))) }
        switch target {
        case .last:
            return .success(running ?? latest(today)!)
        case .named(let name):
            let tracked = distinctTasks(today)
            let index = Ranking.SearchIndex(tasks: tracked)
            var best = bestMatches(name, in: index)
            guard !best.isEmpty else { return .failure(Problem(.problem("Nothing tracked today matches “\(name)”"))) }
            // A tie goes to what's running.
            if best.count > 1, let running, best.contains(where: { $0.key == running.key }) {
                best = best.filter { $0.key == running.key }
            }
            guard best.count == 1 else { return .failure(Problem(ambiguous(name, best))) }
            let entries = today.filter { $0.key == best[0].key }
            return .success(entries.first(where: \.isRunning) ?? latest(entries)!)
        }
    }

    /// The task a name means, among everything you can track. Ties go to a
    /// task you tracked today, then to the one you use most.
    func task(named name: String) -> Result<TrackableTask, Problem> {
        var best = bestMatches(name, in: tasks)
        guard !best.isEmpty else { return .failure(Problem(.problem("No task matches “\(name)”"))) }
        if best.count > 1 {
            let todays = Set(today.map(\.key))
            let tracked = best.filter { todays.contains($0.key) }
            if !tracked.isEmpty { best = tracked }
        }
        if best.count > 1 {
            let ranked = best.sorted { (usage[$0.key] ?? 0) > (usage[$1.key] ?? 0) }
            let top = usage[ranked[0].key] ?? 0
            if top > 0, top > (usage[ranked[1].key] ?? 0) { best = [ranked[0]] }
        }
        guard best.count == 1 else { return .failure(Problem(ambiguous(name, best))) }
        return .success(best[0])
    }

    /// The tasks tied for the best match by name: exact matches first, then
    /// by how well the words matched.
    private func bestMatches(_ name: String, in index: Ranking.SearchIndex) -> [TrackableTask] {
        let matches = index.matches(name)
        guard !matches.isEmpty else { return [] }
        let target = Self.normalize(name)
        // Typing a task's whole name ("Admin", "Website Redesign Design") settles it.
        let exact = matches.filter { match in
            let t = match.task
            let parts = t.projectNameParts.name
            return [t.task.name, t.project.name, parts, "\(parts) \(t.task.name)", "\(t.task.name) \(parts)"]
                .map(Self.normalize).contains(target)
        }
        if !exact.isEmpty {
            let byTask = exact.filter { Self.normalize($0.task.task.name) == target }
            return (byTask.isEmpty ? exact : byTask).map(\.task)
        }
        let kind = matches.map(\.kind).min()!
        let sameKind = matches.filter { $0.kind == kind }
        let top = sameKind.map(\.score).max()!
        return sameKind.filter { $0.score >= top - 0.001 }.map(\.task)
            .sorted { ($0.project.name, $0.task.name) < ($1.project.name, $1.task.name) }
    }

    private func ambiguous(_ name: String, _ tasks: [TrackableTask]) -> AskCommandPlan {
        let choices = tasks.prefix(4).map { "\($0.projectNameParts.name) · \($0.task.name)" }
        let more = tasks.count > 4 ? " (\(tasks.count) in all)" : ""
        return .problem("“\(name)” matches more than one task\(more)", choices: Array(choices))
    }

    private func distinctTasks(_ entries: [TimeEntry]) -> [TrackableTask] {
        var seen = Set<TaskKey>()
        return entries.compactMap { seen.insert($0.key).inserted ? taskFor($0) : nil }
    }

    private func latest(_ entries: [TimeEntry]) -> TimeEntry? {
        entries.max { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    // MARK: Words

    /// A short name for a task in a sentence: its project, or the task when
    /// that's the name you typed ("Admin" rather than "Internal").
    func label(_ task: TrackableTask, typed: String? = nil) -> String {
        let project = task.projectNameParts.name
        var name = project
        if let typed {
            let t = Self.normalize(typed)
            if !t.isEmpty, Self.normalize(task.task.name).contains(t), !Self.normalize(project).contains(t) { name = task.task.name }
        }
        return name.count <= 28 ? name : String(name.prefix(27)) + "…"
    }

    private func full(_ task: TrackableTask) -> String {
        "\(task.projectNameParts.name) · \(task.task.name)"
    }

    private func words(for command: AskCommand, plan: AskCommandPlan) -> (String, String?) {
        let hm = { (hours: Double) in TimeFormat.hoursMinutes(hours * 3600) }
        switch plan {
        case .move(let seconds, let entry, let task):
            let source = taskFor(entry)
            let left = max(0, entry.elapsed(at: now) - seconds)
            var typedFrom: String?, typedTo: String?
            if case .move(_, let from, let to) = command {
                if case .named(let name) = from { typedFrom = name }
                typedTo = to
            }
            return ("Move \(hm(seconds / 3600)) from \(label(source, typed: typedFrom)) to \(label(task, typed: typedTo)) · leaves \(hm(left / 3600))",
                    "\(full(source)) → \(full(task))" + (entry.isRunning ? " · timer keeps running" : ""))
        case .setHours(let entry, let hours):
            let task = taskFor(entry)
            let was = entry.elapsed(at: now) / 3600
            var typed: String?
            if case .setHours(.named(let name), _) = command { typed = name }
            return ("Set \(label(task, typed: typed)) to \(hm(hours)) · was \(hm(was))",
                    full(task) + (entry.isRunning ? " · stops the timer" : ""))
        case .note(let entry, let text):
            let task = taskFor(entry)
            let old = entry.notes.flatMap { $0.isEmpty ? nil : $0 }
            return ("Note on \(label(task)): “\(text)”",
                    full(task) + (old.map { " · replaces “\($0)”" } ?? ""))
        case .pause(let entry):
            let task = taskFor(entry)
            return ("Pause \(label(task)) · \(hm(entry.elapsed(at: now) / 3600)) so far", full(task))
        case .problem(let message, let choices):
            let verb: String = switch command {
            case .move: "Can't move time"
            case .setHours: "Can't change the time"
            case .note: "Can't add the note"
            case .pause: "Can't pause"
            }
            guard let last = choices.last else { return ("\(verb): \(message)", nil) }
            let list = choices.count == 1 ? last : choices.dropLast().joined(separator: ", ") + " or " + last
            return ("\(verb): \(message)", "\(list)? Add a word to pick one.")
        }
    }
}

extension TimeTracker {
    /// For the ask box: the command typed, matched to today's entries, or nil
    /// when the text isn't a command.
    public func askCommand(_ text: String, at now: Date = .now) -> AskCommandPreview? {
        guard let command = AskCommand.parse(text) else { return nil }
        let resolver = AskCommandResolver(
            today: todayEntries, tasks: searchIndex, usage: usage, taskFor: task(for:),
            unavailable: { self.unavailability(of: $0)?.detail }, now: now
        )
        return resolver.preview(command)
    }

    /// Carries out a previewed command through the same methods the rest of
    /// the app uses, so undo and error messages work the same. Returns
    /// whether it worked.
    @discardableResult
    public func perform(_ plan: AskCommandPlan) async -> Bool {
        switch plan {
        case .move(let seconds, let entry, let task):
            return await moveTime(seconds, from: entry, to: task)
        case .setHours(let entry, let hours):
            await updateEntry(entry, task: task(for: entry), notes: entry.notes ?? "", hours: hours)
            return errorMessage == nil
        case .note(let entry, let text):
            await updateEntry(entry, task: task(for: entry), notes: text, hours: nil)
            return errorMessage == nil
        case .pause:
            await pause()
            return errorMessage == nil
        case .problem:
            return false
        }
    }
}
