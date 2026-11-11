import Foundation

/// Where a week's time went, for Monday planning: the total against last
/// week and a usual week, by client and project, billable against internal,
/// the top tasks, and each day's hours.
public struct WeeklySummary: Equatable, Sendable {
    public struct Project: Equatable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let seconds: TimeInterval
    }

    public struct Client: Equatable, Sendable, Identifiable {
        /// The client's Harvest id; 0 for time with no client.
        public let id: Int
        public let name: String
        public let seconds: TimeInterval
        public let projects: [Project]
    }

    public struct TaskTotal: Equatable, Sendable, Identifiable {
        public let key: TaskKey
        public let task: String
        public let project: String
        public let client: String?
        public let seconds: TimeInterval
        public var id: TaskKey { key }
    }

    public struct Day: Equatable, Sendable, Identifiable {
        public let date: LocalDate
        public let seconds: TimeInterval
        public var id: LocalDate { date }
    }

    public let weekStart: LocalDate
    public var weekEnd: LocalDate { weekStart.adding(days: 6) }
    public let total: TimeInterval
    /// Last week's total, or, while this week is still going, last week's
    /// total up to the same weekday (see `comparesThrough`).
    public let previousTotal: TimeInterval
    /// When the week is in progress, the last day counted on both sides of
    /// the week-over-week comparison; nil for a finished week.
    public let comparesThrough: LocalDate?
    /// The mean of the previous few weeks that have any time in them; nil
    /// when none do.
    public let usualTotal: TimeInterval?
    public let billable: TimeInterval
    public let `internal`: TimeInterval
    /// Biggest first, projects biggest first within each client.
    public let clients: [Client]
    public let topTasks: [TaskTotal]
    /// Seven days from `weekStart`.
    public let days: [Day]

    public var change: TimeInterval { total - previousTotal }
    public var changeFromUsual: TimeInterval? { usualTotal.map { total - $0 } }

    /// `part`'s share of the week, 0–1.
    public func share(_ part: TimeInterval) -> Double {
        total > 0 ? part / total : 0
    }

    public var isEmpty: Bool { total <= 0 }

    /// How many earlier weeks make up the usual week.
    public static let usualWeeks = 4
    public static let topTaskCount = 5

    /// Builds the summary for the week starting `weekStart` from whatever
    /// entries are loaded. `today` decides whether the week is still going;
    /// a running timer counts up to `now`.
    public static func make(
        entries: [TimeEntry], weekStart: LocalDate, today: LocalDate = LocalDate(), now: Date = .now
    ) -> WeeklySummary {
        let weekEnd = weekStart.adding(days: 6)
        let week = entries.filter { $0.spentDate >= weekStart && $0.spentDate <= weekEnd }

        func seconds(_ entries: some Sequence<TimeEntry>) -> TimeInterval {
            entries.reduce(0) { $0 + $1.elapsed(at: now) }
        }
        func sum(from start: LocalDate, through end: LocalDate) -> TimeInterval {
            seconds(entries.lazy.filter { $0.spentDate >= start && $0.spentDate <= end })
        }

        let total = seconds(week)

        // While the week is still going, compare like with like: last week
        // up to the same weekday.
        let inProgress = today >= weekStart && today < weekEnd
        let comparesThrough = inProgress ? today : nil
        let previousStart = weekStart.adding(days: -7)
        let previousEnd = inProgress ? today.adding(days: -7) : previousStart.adding(days: 6)
        let previousTotal = sum(from: previousStart, through: previousEnd)

        let earlier = (1...usualWeeks).map { back -> TimeInterval in
            let start = weekStart.adding(days: -7 * back)
            return sum(from: start, through: start.adding(days: 6))
        }.filter { $0 > 0 }
        let usualTotal = earlier.isEmpty ? nil : earlier.reduce(0, +) / Double(earlier.count)

        var billable: TimeInterval = 0
        for entry in week where isBillable(entry) { billable += entry.elapsed(at: now) }

        // Client → project.
        let byClient = Dictionary(grouping: week) { $0.client?.id ?? 0 }
        let clients = byClient.map { id, entries -> Client in
            let projects = Dictionary(grouping: entries, by: \.project.id).map { pid, entries in
                Project(id: pid, name: entries[0].project.name, seconds: seconds(entries))
            }
            return Client(
                id: id, name: entries[0].client?.name ?? "No client", seconds: seconds(entries),
                projects: projects.sorted(by: biggestFirst)
            )
        }.sorted(by: biggestFirst)

        let topTasks = Dictionary(grouping: week, by: \.key).map { key, entries in
            TaskTotal(key: key, task: entries[0].task.name, project: entries[0].project.name,
                      client: entries[0].client?.name, seconds: seconds(entries))
        }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : ($0.project, $0.task) < ($1.project, $1.task) }
        .prefix(topTaskCount)

        let days = (0..<7).map { offset -> Day in
            let day = weekStart.adding(days: offset)
            return Day(date: day, seconds: seconds(week.lazy.filter { $0.spentDate == day }))
        }

        return WeeklySummary(
            weekStart: weekStart, total: total, previousTotal: previousTotal, comparesThrough: comparesThrough,
            usualTotal: usualTotal, billable: billable, internal: total - billable,
            clients: clients, topTasks: Array(topTasks), days: days
        )
    }

    private static func biggestFirst<T: Named>(_ a: T, _ b: T) -> Bool {
        a.seconds != b.seconds ? a.seconds > b.seconds : a.name.localizedStandardCompare(b.name) == .orderedAscending
    }

    /// Harvest's own billable flag when it sent one. Otherwise internal is
    /// Tractorbeam's own time: `[TB-DP-xx]` department projects, or anything
    /// for the Tractorbeam client.
    public static func isBillable(_ entry: TimeEntry) -> Bool {
        if let billable = entry.billable { return billable }
        return !isInternal(projectName: entry.project.name, clientName: entry.client?.name)
    }

    static func isInternal(projectName: String, clientName: String?) -> Bool {
        if projectName.uppercased().hasPrefix("[TB-DP-") { return true }
        return clientName?.localizedCaseInsensitiveContains("Tractorbeam") == true
    }
}

private protocol Named {
    var name: String { get }
    var seconds: TimeInterval { get }
}
extension WeeklySummary.Client: Named {}
extension WeeklySummary.Project: Named {}

// MARK: - Text

extension WeeklySummary {
    /// "Nov 9 – 15, 2026" (or across months, "Oct 26 – Nov 1, 2026").
    public var rangeTitle: String {
        let start = weekStart.date(), end = weekEnd.date()
        let sameMonth = weekStart.month == weekEnd.month
        let first = start.formatted(.dateTime.month(.abbreviated).day())
        let last = sameMonth ? end.formatted(.dateTime.day()) : end.formatted(.dateTime.month(.abbreviated).day())
        return "\(first) – \(last), \(weekEnd.year)"
    }

    /// "+3:15", "−1:05" or "±0:00".
    public static func signed(_ seconds: TimeInterval) -> String {
        let rounded = (seconds / 60).rounded()
        let sign = rounded > 0 ? "+" : rounded < 0 ? "−" : "±"
        return sign + TimeFormat.hoursMinutes(abs(rounded) * 60)
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    /// Plain text for pasting into Slack: no markdown tables, just lines that
    /// read well in a proportional font.
    public var plainText: String {
        let h = TimeFormat.hoursMinutes
        var lines = ["Weekly summary · \(rangeTitle)", ""]
        var total = "Total: \(h(self.total))"
        if comparesThrough != nil {
            total += " so far (\(Self.signed(change)) vs last week by this day)"
        } else {
            total += " (\(Self.signed(change)) vs last week"
            if let changeFromUsual { total += ", \(Self.signed(changeFromUsual)) vs a usual week" }
            total += ")"
        }
        lines.append(total)
        guard !isEmpty else {
            lines.append("No time tracked.")
            return lines.joined(separator: "\n")
        }
        lines.append("Billable: \(h(billable)) (\(Self.percent(share(billable)))) · Internal: \(h(self.internal)) (\(Self.percent(share(self.internal))))")

        lines += ["", "By client"]
        for client in clients {
            lines.append("• \(client.name) — \(h(client.seconds)) (\(Self.percent(share(client.seconds))))")
            for project in client.projects {
                lines.append("    ◦ \(project.name) — \(h(project.seconds))")
            }
        }

        lines += ["", "Top tasks"]
        for (index, task) in topTasks.enumerated() {
            lines.append("\(index + 1). \(task.task) · \(task.project) — \(h(task.seconds))")
        }

        lines += ["", "By day"]
        let dayLine = days.map { day in
            let name = day.date.date().formatted(.dateTime.weekday(.abbreviated))
            return "\(name) \(h(day.seconds))"
        }
        lines.append(dayLine.joined(separator: " · "))
        return lines.joined(separator: "\n")
    }
}
