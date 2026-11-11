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
    ///
    /// Words of four letters or more also forgive typos ("researhc", "desgin"):
    /// a query word may be a few edits away from a whole word in a field. Tasks
    /// that need a typo to match always rank below tasks that match exactly.
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
        /// Every distinct word in the index, grouped by length, for typo lookups.
        let vocabulary: [Int: [(word: String, scalars: [Unicode.Scalar])]]

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
            var seen = Set<String>()
            var vocabulary: [Int: [(word: String, scalars: [Unicode.Scalar])]] = [:]
            for item in items {
                for field in item.fields {
                    for word in field.words where seen.insert(word).inserted {
                        let scalars = Array(word.unicodeScalars)
                        vocabulary[scalars.count, default: []].append((word, scalars))
                    }
                }
            }
            self.vocabulary = vocabulary
        }

        public func search(_ query: String, usage: [TaskKey: Double] = [:], favorites: Set<TaskKey> = []) -> [TrackableTask] {
            let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
            guard !tokens.isEmpty else { return [] }
            // Words within reach of each query word, worked out once per query
            // rather than once per task.
            let near = tokens.map(nearWords)

            var scored: [(task: TrackableTask, fuzzy: Bool, score: Double)] = []
            items: for item in items {
                var total = 0.0
                var fuzzy = false
                for (token, near) in zip(tokens, near) {
                    var best = 0.0
                    for field in item.fields {
                        best = max(best, matchScore(token, in: field) * field.weight)
                    }
                    if best == 0, !near.isEmpty {
                        for field in item.fields {
                            for word in field.words {
                                if let distance = near[word] { best = max(best, field.weight / Double(distance + 1) / 2) }
                            }
                        }
                        fuzzy = best > 0
                    }
                    guard best > 0 else { continue items }
                    total += best
                }
                total += min(usage[item.task.key] ?? 0, 5) * 0.4
                if favorites.contains(item.task.key) { total += 1.5 }
                scored.append((item.task, fuzzy, total))
            }
            return scored
                .sorted {
                    if $0.fuzzy != $1.fuzzy { return !$0.fuzzy }
                    return $0.score != $1.score ? $0.score > $1.score : $0.task.task.name < $1.task.task.name
                }
                .map(\.task)
        }

        private func matchScore(_ token: String, in field: Field) -> Double {
            if field.text.hasPrefix(token) { return 3 }
            if field.words.contains(where: { $0.hasPrefix(token) }) { return 2 }
            if field.text.contains(token) { return 1 }
            return 0
        }

        /// Index words a typo away from `token`, with their edit distance.
        /// Empty for words shorter than four letters.
        private func nearWords(_ token: String) -> [String: Int] {
            let scalars = Array(token.unicodeScalars)
            let allowed = Ranking.allowedEdits(forLength: scalars.count)
            guard allowed > 0 else { return [:] }
            var result: [String: Int] = [:]
            for length in (scalars.count - allowed)...(scalars.count + allowed) {
                for entry in vocabulary[length] ?? [] {
                    if let distance = Ranking.editDistance(scalars, entry.scalars, limit: allowed) {
                        result[entry.word] = distance
                    }
                }
            }
            return result
        }
    }

    /// Typos forgiven in a query word: none up to three letters, one up to
    /// seven, two beyond.
    static func allowedEdits(forLength length: Int) -> Int {
        switch length {
        case ..<4: 0
        case 4...7: 1
        default: 2
        }
    }

    /// Damerau–Levenshtein distance (optimal string alignment: insertions,
    /// deletions, substitutions and swaps of neighbors each cost one), or nil
    /// when it's more than `limit`.
    static func editDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar], limit: Int) -> Int? {
        if abs(a.count - b.count) > limit { return nil }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var previous2 = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMin = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    value = min(value, previous2[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return nil }
            (previous2, previous, current) = (previous, current, previous2)
        }
        let distance = previous[b.count]
        return distance <= limit ? distance : nil
    }

    static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
