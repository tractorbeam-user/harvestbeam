import Foundation

/// Pure functions behind the Recent, Suggested and search lists, kept free of
/// state so they're easy to test.
public enum Ranking {
    /// Distinct tasks, most recently tracked first.
    public static func recent(
        from entries: [TimeEntry],
        excluding excluded: Set<TaskKey> = [],
        limit: Int = 5
    ) -> [TaskKey] {
        let sorted = entries.sorted {
            ($0.spentDate, $0.updatedAt) > ($1.spentDate, $1.updatedAt)
        }
        var seen = excluded
        var result: [TaskKey] = []
        for entry in sorted where seen.insert(entry.key).inserted {
            result.append(entry.key)
            if result.count == limit { break }
        }
        return result
    }

    /// How strongly the user's history points at each task: every entry adds a
    /// weight that halves every `halfLifeDays`, with a bump for entries on the
    /// same weekday as today (Monday standups, Friday invoicing).
    public static func usageScores(
        from entries: [TimeEntry],
        today: LocalDate = LocalDate(),
        halfLifeDays: Double = 14
    ) -> [TaskKey: Double] {
        let todayWeekday = today.weekday
        var scores: [TaskKey: Double] = [:]
        for entry in entries {
            let age = max(0, entry.spentDate.days(until: today))
            var weight = pow(0.5, Double(age) / halfLifeDays)
            if entry.spentDate.weekday == todayWeekday { weight *= 1.5 }
            scores[entry.key, default: 0] += weight
        }
        return scores
    }

    /// Highest-scoring tasks that aren't already shown elsewhere.
    public static func suggested(
        scores: [TaskKey: Double],
        excluding excluded: Set<TaskKey> = [],
        limit: Int = 5
    ) -> [TaskKey] {
        scores
            .filter { !excluded.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.description < $1.key.description }
            .prefix(limit)
            .map(\.key)
    }

    public static func suggested(
        from entries: [TimeEntry],
        excluding excluded: Set<TaskKey> = [],
        today: LocalDate = LocalDate(),
        limit: Int = 5
    ) -> [TaskKey] {
        suggested(scores: usageScores(from: entries, today: today), excluding: excluded, limit: limit)
    }

    public static func search(
        _ query: String,
        in tasks: [TrackableTask],
        usage: [TaskKey: Double] = [:],
        favorites: Set<TaskKey> = []
    ) -> [TrackableTask] {
        SearchIndex(tasks: tasks).search(query, usage: usage, favorites: favorites)
    }

    /// Task names normalized once up front, so typing in the search field only
    /// does cheap string comparisons.
    ///
    /// Every word of the query has to match the task, project, project code or
    /// client. Prefix matches beat substring matches, task names beat project
    /// names, and favorites and frequently used tasks float up on ties.
    public struct SearchIndex: Sendable {
        struct Field: Sendable {
            let text: String
            let words: [String]
            let weight: Double
        }

        struct Item: Sendable {
            let task: TrackableTask
            let fields: [Field]
        }

        let items: [Item]

        public init(tasks: [TrackableTask]) {
            func field(_ raw: String?, _ weight: Double) -> Field? {
                guard let raw, !raw.isEmpty else { return nil }
                let text = normalize(raw)
                let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
                return Field(text: text, words: words, weight: weight)
            }
            items = tasks.map { task in
                Item(task: task, fields: [
                    field(task.task.name, 3),
                    field(task.project.name, 2),
                    field(task.projectCode, 2),
                    field(task.client?.name, 1),
                ].compactMap { $0 })
            }
        }

        public func search(_ query: String, usage: [TaskKey: Double] = [:], favorites: Set<TaskKey> = []) -> [TrackableTask] {
            let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { return [] }

            var scored: [(TrackableTask, Double)] = []
            items: for item in items {
                var total = 0.0
                for token in tokens {
                    var best = 0.0
                    for field in item.fields {
                        best = max(best, matchScore(token, in: field) * field.weight)
                    }
                    guard best > 0 else { continue items }
                    total += best
                }
                total += min(usage[item.task.key] ?? 0, 5) * 0.4
                if favorites.contains(item.task.key) { total += 1.5 }
                scored.append((item.task, total))
            }
            return scored
                .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.task.name < $1.0.task.name }
                .map(\.0)
        }

        private func matchScore(_ token: String, in field: Field) -> Double {
            if field.text.hasPrefix(token) { return 3 }
            if field.words.contains(where: { $0.hasPrefix(token) }) { return 2 }
            if field.text.contains(token) { return 1 }
            return 0
        }
    }

    static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
