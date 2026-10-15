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
        halfLifeDays: Double = 14,
        calendar: Calendar = .current
    ) -> [TaskKey: Double] {
        let todayWeekday = today.weekday(calendar: calendar)
        var scores: [TaskKey: Double] = [:]
        for entry in entries {
            let age = max(0, entry.spentDate.days(until: today, calendar: calendar))
            var weight = pow(0.5, Double(age) / halfLifeDays)
            if entry.spentDate.weekday(calendar: calendar) == todayWeekday { weight *= 1.5 }
            scores[entry.key, default: 0] += weight
        }
        return scores
    }

    /// Tasks used most often (recency-weighted) that aren't already shown elsewhere.
    public static func suggested(
        from entries: [TimeEntry],
        excluding excluded: Set<TaskKey> = [],
        today: LocalDate = LocalDate(),
        limit: Int = 5,
        calendar: Calendar = .current
    ) -> [TaskKey] {
        usageScores(from: entries, today: today, calendar: calendar)
            .filter { !excluded.contains($0.key) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.description < $1.key.description }
            .prefix(limit)
            .map(\.key)
    }

    /// Matches every word of `query` against task, project, client and project
    /// code. Prefix matches beat substring matches, task names beat project
    /// names, and frequently used tasks float up on ties.
    public static func search(
        _ query: String,
        in tasks: [TrackableTask],
        usage: [TaskKey: Double] = [:],
        favorites: Set<TaskKey> = []
    ) -> [TrackableTask] {
        let tokens = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }

        let scored: [(TrackableTask, Double)] = tasks.compactMap { task in
            let fields: [(String, Double)] = [
                (normalize(task.task.name), 3),
                (normalize(task.project.name), 2),
                (normalize(task.projectCode ?? ""), 2),
                (normalize(task.client?.name ?? ""), 1),
            ]
            var total = 0.0
            for token in tokens {
                let best = fields.map { matchScore(token, in: $0.0) * $0.1 }.max() ?? 0
                guard best > 0 else { return nil }
                total += best
            }
            total += min(usage[task.key] ?? 0, 5) * 0.4
            if favorites.contains(task.key) { total += 1.5 }
            return (task, total)
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.task.name < $1.0.task.name }
            .map(\.0)
    }

    static func matchScore(_ token: String, in field: String) -> Double {
        guard !field.isEmpty else { return 0 }
        if field.hasPrefix(token) { return 3 }
        if field.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(token) }) { return 2 }
        if field.contains(token) { return 1 }
        return 0
    }

    static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
