import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One time entry proposed from a plain-text description of the day.
public struct PlannedEntry: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public var task: TrackableTask
    /// Nil when the text didn't say how long; today that can start a timer.
    public var hours: Double?
    public var notes: String

    public init(task: TrackableTask, hours: Double?, notes: String) {
        self.task = task
        self.hours = hours
        self.notes = notes
    }
}

/// Turns "Context design all morning, an hour on the LP site, client call"
/// into proposed entries. Uses Apple's on-device model when it's available,
/// choosing only from a shortlist the app's own search builds, and falls back
/// to keyword matching otherwise.
public enum DayPlanner {
    public enum Engine: Sendable { case onDeviceModel, keywords }

    /// Whether Apple's on-device model can be used right now.
    public static var modelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Plans the text. `search` is the app's task search; `familiar` are tasks
    /// the person uses a lot (recent, favorites), offered to the model too.
    public static func plan(
        _ text: String,
        search: @Sendable (String) -> [TrackableTask],
        familiar: [TrackableTask]
    ) async -> (entries: [PlannedEntry], engine: Engine) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), modelAvailable {
            let shortlist = candidates(for: text, search: search, familiar: familiar)
            if !shortlist.isEmpty, let entries = try? await planWithModel(text, candidates: shortlist), !entries.isEmpty {
                return (entries, .onDeviceModel)
            }
        }
        #endif
        return (planWithKeywords(text, search: search), .keywords)
    }

    // MARK: Text

    /// Splits on line breaks, commas, semicolons, periods and "then".
    static func clauses(_ text: String) -> [String] {
        var normalized = " " + text.lowercased() + " "
        for joiner in [" and then ", " then ", " after that ", " plus ", " also "] {
            normalized = normalized.replacingOccurrences(of: joiner, with: ",")
        }
        return normalized
            .split(whereSeparator: { ",;.\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Hours mentioned in a clause: "2h", "1.5 hours", "90 min", "1:30",
    /// "an hour", "half an hour", "all morning".
    static func hours(in clause: String) -> Double? {
        let text = clause.lowercased()
        if let match = text.firstMatch(of: /(\d+):(\d{2})/), let h = Double(match.1), let m = Double(match.2) {
            return h + m / 60
        }
        if let match = text.firstMatch(of: /(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b/), let h = Double(match.1) {
            return h
        }
        if let match = text.firstMatch(of: /(\d+)\s*(?:m|min|mins|minute|minutes)\b/), let m = Double(match.1) {
            return m / 60
        }
        if text.contains("half an hour") || text.contains("half hour") { return 0.5 }
        if text.contains("an hour") || text.contains("one hour") { return 1 }
        if text.contains("all day") { return 8 }
        if text.contains("morning") { return 3 }
        if text.contains("afternoon") { return 4 }
        return nil
    }

    /// Whether a phrase talks about how long: an explicit amount, or a time of
    /// day like "till lunch".
    static func mentionsDuration(_ phrase: String) -> Bool {
        if hours(in: phrase) != nil { return true }
        let text = phrase.lowercased()
        return ["lunch", "till", "until", "noon", "eod", "end of day"].contains { text.contains($0) }
    }

    private static let fillers: Set<String> = [
        "a", "an", "the", "on", "in", "for", "of", "to", "with", "at", "some", "more", "my", "and", "then",
        "work", "working", "worked", "doing", "do", "did", "today", "all", "morning", "afternoon", "day",
        "hour", "hours", "hr", "hrs", "h", "min", "mins", "minute", "minutes", "half", "about", "around", "i", "i'm", "im",
    ]

    /// The words in a clause worth searching for.
    static func keywords(in clause: String) -> [String] {
        clause.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
            .map(String.init)
            .filter { !fillers.contains($0) && Double($0) == nil && $0.count > 1 }
    }

    // MARK: Keyword fallback

    /// Best search match per clause: every keyword if possible, otherwise the
    /// keywords that match something on their own.
    static func planWithKeywords(_ text: String, search: (String) -> [TrackableTask]) -> [PlannedEntry] {
        clauses(text).compactMap { clause in
            let words = keywords(in: clause)
            guard !words.isEmpty else { return nil }
            var match = search(words.joined(separator: " ")).first
            if match == nil {
                let useful = words.filter { !search($0).isEmpty }
                match = search(useful.joined(separator: " ")).first
                for word in useful where match == nil { match = search(word).first }
            }
            guard let match else { return nil }
            return PlannedEntry(task: match, hours: hours(in: clause), notes: "")
        }
    }

    // MARK: On-device model

    /// What the model may choose from: search hits per clause and per word,
    /// plus familiar tasks. Capped so the prompt stays small.
    static func candidates(for text: String, search: (String) -> [TrackableTask], familiar: [TrackableTask]) -> [TrackableTask] {
        var seen = Set<TaskKey>()
        var result: [TrackableTask] = []
        func add(_ tasks: some Sequence<TrackableTask>, limit: Int) {
            var added = 0
            for task in tasks where added < limit && seen.insert(task.key).inserted {
                result.append(task)
                added += 1
            }
        }
        for clause in clauses(text) {
            let words = keywords(in: clause)
            add(search(words.joined(separator: " ")), limit: 6)
            for word in words { add(search(word), limit: 4) }
        }
        add(familiar, limit: 8)
        return Array(result.prefix(45))
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    static func planWithModel(_ text: String, candidates: [TrackableTask]) async throws -> [PlannedEntry] {
        let ids = candidates.indices.map { "T\($0 + 1)" }
        let list = zip(ids, candidates).map { id, task in
            let project = task.projectCode.map { "[\($0)] \(task.project.name)" } ?? task.project.name
            return "\(id): \(project) — \(task.task.name)" + (task.client.map { " (client: \($0.name))" } ?? "")
        }.joined(separator: "\n")

        let entry = DynamicGenerationSchema(name: "Entry", properties: [
            .init(name: "taskID", description: "ID of the matching task from the list", schema: .init(name: "TaskID", anyOf: ids)),
            .init(name: "hours", description: "Hours they said they'd spend, if they said", schema: .init(type: Double.self), isOptional: true),
            .init(name: "notes", description: "A few words from their description, or empty", schema: .init(type: String.self)),
        ])
        let root = DynamicGenerationSchema(name: "Plan", properties: [
            .init(name: "entries", description: "One entry per piece of work they described, in order",
                  schema: .init(arrayOf: .init(referenceTo: "Entry"), minimumElements: 1, maximumElements: 12)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [entry])

        let session = LanguageModelSession(instructions: """
            You fill in a Harvest timesheet. The person describes what they're working on today in plain words. \
            Split it into separate pieces of work and match each to the single best task from the list, using \
            project names, project codes, clients and task types (design, development, meetings or calls, admin…). \
            Give hours only when they said a duration ("2h", "an hour", "all morning" ≈ 3). Never invent tasks.
            """)
        let prompt = "Tasks:\n\(list)\n\nWhat they said: \"\(text)\""
        let response = try await session.respond(to: prompt, schema: schema, options: GenerationOptions(temperature: 0))

        let byID = Dictionary(uniqueKeysWithValues: zip(ids, candidates))
        return try response.content.value([GeneratedContent].self, forProperty: "entries").compactMap { item in
            guard let id = try? item.value(String.self, forProperty: "taskID"), let task = byID[id] else { return nil }
            let hours = (try? item.value(Double?.self, forProperty: "hours")) ?? nil
            let notes = (try? item.value(String.self, forProperty: "notes")) ?? ""
            // The model sometimes fills in an hour nobody mentioned; keep its
            // hours only when their words talk about time.
            let saidDuration = Self.mentionsDuration(notes)
            return PlannedEntry(task: task, hours: saidDuration ? hours.flatMap { $0 > 0 && $0 <= 24 ? $0 : nil } : nil, notes: notes)
        }
    }
    #endif
}

extension TimeTracker {
    /// Plans the text against this account's tasks.
    public func planDay(_ text: String) async -> (entries: [PlannedEntry], engine: DayPlanner.Engine) {
        let index = searchIndex
        let scores = self.usage
        let starred = favorites.set
        let familiar = recentTasks + favoriteTasks + suggestedTasks
        return await DayPlanner.plan(
            text,
            search: { Array(index.search($0, usage: scores, favorites: starred).prefix(20)) },
            familiar: familiar
        )
    }
}
