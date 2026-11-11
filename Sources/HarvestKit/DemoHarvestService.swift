import Foundation

/// An in-memory Harvest with a few weeks of believable history, for trying the
/// UI without an account and for SwiftUI previews.
public actor DemoHarvestService: HarvestService {
    private var assignments: [ProjectAssignment]
    private var entries: [TimeEntry]
    private var nextID = 10_000
    private let tracksStartAndEnd: Bool

    /// `includesArchivedWork` adds an archived Northwind project with recent
    /// entries, for snapshots of how archived work looks. `reviewWeek` makes
    /// it a start-and-end account whose current week has something for each
    /// part of the Week Review (see `reviewWeekEntries`).
    public init(now: Date = .now, includesArchivedWork: Bool = false, reviewWeek: Bool = false) {
        tracksStartAndEnd = reviewWeek
        let tractorbeam = NamedRef(id: 1, name: "Tractorbeam")
        let acme = NamedRef(id: 2, name: "Acme Co")
        let northwind = NamedRef(id: 3, name: "Northwind")

        let design = NamedRef(id: 11, name: "Design")
        let development = NamedRef(id: 12, name: "Development")
        let meetings = NamedRef(id: 13, name: "Meetings")
        let pm = NamedRef(id: 14, name: "Project Management")
        let strategy = NamedRef(id: 15, name: "Strategy")
        let qa = NamedRef(id: 16, name: "QA & Testing")
        let admin = NamedRef(id: 17, name: "Admin")

        func assignment(_ id: Int, _ name: String, code: String?, client: NamedRef, tasks: [NamedRef]) -> ProjectAssignment {
            ProjectAssignment(
                id: id,
                project: .init(id: id, name: name, code: code),
                client: client,
                taskAssignments: tasks.map { .init(id: id * 100 + $0.id, task: $0) }
            )
        }

        assignments = [
            assignment(101, "Website Redesign", code: "TB-WEB", client: tractorbeam, tasks: [design, development, meetings, qa]),
            assignment(102, "Context Launch", code: "TB-CTX", client: tractorbeam, tasks: [strategy, development, meetings, pm]),
            assignment(103, "Brand Refresh", code: "ACME-BR", client: acme, tasks: [design, strategy, meetings]),
            assignment(104, "Mobile App", code: "ACME-APP", client: acme, tasks: [design, development, qa, pm]),
            assignment(105, "Data Platform", code: "NW-DATA", client: northwind, tasks: [development, meetings, pm]),
            assignment(106, "Internal", code: nil, client: tractorbeam, tasks: [admin, meetings]),
            // Buckets from the team's time-tracking policy (`TaskDefinitions`),
            // one of them retired.
            assignment(108, "[TB-DP-12] Billing", code: nil, client: tractorbeam, tasks: [admin]),
            assignment(109, "[TB-DP-14] Hiring", code: nil, client: tractorbeam, tasks: [admin, meetings]),
            assignment(110, "[TB-DP-19] Business Dev", code: nil, client: tractorbeam, tasks: [strategy, meetings]),
            assignment(111, "Digital Products", code: nil, client: tractorbeam, tasks: [admin]),
        ]
        let springCampaign = ProjectAssignment(
            id: 107, isActive: false, project: .init(id: 107, name: "Spring Campaign", code: "NW-SPR"), client: northwind,
            taskAssignments: [design, meetings].map { .init(id: 10_700 + $0.id, task: $0) }
        )
        if includesArchivedWork { assignments.append(springCampaign) }
        if reviewWeek {
            assignments.append(assignment(108, "Digital Products", code: nil, client: tractorbeam, tasks: [design, development]))
            assignments.append(assignment(109, "Business Dev", code: nil, client: tractorbeam, tasks: [strategy]))
        }

        // Deterministic history: a weighted handful of tasks most days.
        let pattern: [(Int, NamedRef, NamedRef, Double)] = [
            (101, design, tractorbeam, 9), (102, development, tractorbeam, 7), (106, meetings, tractorbeam, 6),
            (103, design, acme, 4), (104, qa, acme, 3), (105, development, northwind, 3),
            (102, strategy, tractorbeam, 2), (106, admin, tractorbeam, 2), (104, pm, acme, 1),
        ]
        let projectNames = Dictionary(uniqueKeysWithValues: assignments.map { ($0.project.id, $0.project.name) })
        var generated: [TimeEntry] = []
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(UInt64(1) << 31)
        }
        let today = LocalDate(now)
        var id = 1
        for daysAgo in 0..<35 {
            let day = today.adding(days: -daysAgo)
            guard ![1, 7].contains(day.weekday) else { continue }
            let totalWeight = pattern.reduce(0) { $0 + $1.3 }
            for (projectID, task, client, weight) in pattern where random() < weight / totalWeight * 3 {
                let stamp = day.date().addingTimeInterval(9 * 3600 + random() * 8 * 3600)
                // Older Acme work is invoiced; last week's is approved.
                let invoiced = daysAgo >= 14 && client == acme
                let approved = !invoiced && (7..<14).contains(daysAgo)
                generated.append(TimeEntry(
                    id: id, spentDate: day,
                    project: NamedRef(id: projectID, name: projectNames[projectID]!), task: task, client: client,
                    hours: (random() * 3 + 0.25).rounded(toPlaces: 2),
                    createdAt: stamp, updatedAt: stamp,
                    isLocked: invoiced || approved, isClosed: approved, isBilled: invoiced,
                    invoice: invoiced ? .init(id: 1042, number: "1042") : nil,
                    billable: client != tractorbeam
                ))
                id += 1
            }
        }
        if includesArchivedWork {
            // Work on the now-archived Spring Campaign: yesterday, and an
            // approved stretch the week before last.
            for (daysAgo, task, hours, approved) in [(1, design, 1.5, false), (10, design, 2.25, true), (10, meetings, 0.5, true)] {
                let day = today.adding(days: -daysAgo)
                let stamp = day.date().addingTimeInterval(8 * 3600)
                generated.append(TimeEntry(
                    id: id, spentDate: day, project: NamedRef(id: 107, name: "Spring Campaign"), task: task, client: northwind,
                    hours: hours, notes: daysAgo == 1 ? "Final asset handoff" : nil, createdAt: stamp, updatedAt: stamp,
                    isLocked: approved, isClosed: approved
                ))
                id += 1
            }
        }
        // A timer that's been running for 47 minutes.
        generated.append(TimeEntry(
            id: id, spentDate: today,
            project: NamedRef(id: 101, name: "Website Redesign"), task: design, client: tractorbeam,
            hours: 0.78, hoursWithoutTimer: 0, notes: "Menu bar timer explorations",
            isRunning: true, timerStartedAt: now.addingTimeInterval(-47 * 60), createdAt: now, updatedAt: now
        ))
        if reviewWeek {
            let monday = today.startOfWeek(firstWeekday: 2)
            generated.removeAll { $0.spentDate >= monday }
            generated += Self.reviewWeekEntries(monday: monday, now: now, firstID: id + 1)
        }
        entries = generated
    }

    /// A start-and-end week, as of its Friday at 4 PM: Monday has a retired
    /// "Digital Products" entry; Tuesday is short, with a gap under a meeting
    /// and one with nothing; Wednesday is empty; Thursday has a legacy
    /// "Business Dev" entry and a timer still running; Friday has an entry
    /// with no notes.
    static func reviewWeekEntries(monday: LocalDate, now: Date, firstID: Int) -> [TimeEntry] {
        let projects: [Int: (String, NamedRef)] = [
            101: ("Website Redesign", NamedRef(id: 1, name: "Tractorbeam")), 102: ("Context Launch", NamedRef(id: 1, name: "Tractorbeam")),
            103: ("Brand Refresh", NamedRef(id: 2, name: "Acme Co")), 104: ("Mobile App", NamedRef(id: 2, name: "Acme Co")),
            105: ("Data Platform", NamedRef(id: 3, name: "Northwind")), 106: ("Internal", NamedRef(id: 1, name: "Tractorbeam")),
            108: ("Digital Products", NamedRef(id: 1, name: "Tractorbeam")), 109: ("Business Dev", NamedRef(id: 1, name: "Tractorbeam")),
        ]
        let tasks: [Int: String] = [11: "Design", 12: "Development", 13: "Meetings", 15: "Strategy", 16: "QA & Testing"]
        let plan: [(day: Int, from: String, to: String?, project: Int, task: Int, notes: String?)] = [
            (0, "9:00am", "9:30am", 106, 13, "Standup"),
            (0, "9:30am", "1:00pm", 101, 11, "Homepage hero"),
            (0, "1:00pm", "3:30pm", 102, 12, "API wiring"),
            (0, "3:30pm", "6:00pm", 108, 11, "Banner set"),
            (1, "9:00am", "9:30am", 106, 13, "Standup"),
            (1, "9:30am", "11:00am", 103, 11, "Logo options"),
            (1, "11:00am", "1:00pm", 104, 16, nil),
            (1, "2:00pm", "3:30pm", 101, 11, "Nav states"),
            (3, "9:00am", "12:00pm", 102, 15, "Launch brief"),
            (3, "12:00pm", "1:00pm", 109, 15, "Intro call with Globex"),
            (3, "1:00pm", nil, 105, 12, "Pipeline migration"),
            (4, "9:00am", "9:30am", 106, 13, "Standup"),
            (4, "9:30am", "12:00pm", 104, 11, "Onboarding screens"),
            (4, "12:00pm", "4:00pm", 104, 12, nil),
        ]
        return plan.enumerated().map { index, item in
            let day = monday.adding(days: item.day)
            let start = ClockTime.minutes(item.from)!
            let created = day.date().addingTimeInterval(Double(start) * 60)
            let (project, client) = projects[item.project]!
            let task = NamedRef(id: item.task, name: tasks[item.task]!)
            guard let to = item.to else {
                // Left running since Thursday afternoon: five hours so far.
                return TimeEntry(id: firstID + index, spentDate: day, project: NamedRef(id: item.project, name: project), task: task,
                                 client: client, hours: 5, hoursWithoutTimer: 0, notes: item.notes, isRunning: true,
                                 timerStartedAt: now.addingTimeInterval(-5 * 3600), startedTime: item.from,
                                 createdAt: created, updatedAt: created)
            }
            let hours = Double(ClockTime.minutes(to)! - start) / 60
            return TimeEntry(id: firstID + index, spentDate: day, project: NamedRef(id: item.project, name: project), task: task,
                             client: client, hours: hours, notes: item.notes, startedTime: item.from, endedTime: to,
                             createdAt: created, updatedAt: created)
        }
    }

    public func currentUser() async throws -> HarvestUser {
        HarvestUser(id: 1, firstName: "Demo", lastName: "User", email: "demo@example.com", weeklyCapacity: 40 * 3600)
    }

    public func company() async throws -> Company {
        Company(baseUri: "https://example.harvestapp.com", name: "Tractorbeam (demo)",
                wantsTimestampTimers: tracksStartAndEnd, weekStartDay: "Monday")
    }

    public func projectAssignments() async throws -> [ProjectAssignment] {
        assignments
    }

    public func timeEntries(userID: Int, from: LocalDate, to: LocalDate) async throws -> [TimeEntry] {
        entries.filter { $0.spentDate >= from && $0.spentDate <= to }
    }

    public func startTimer(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?) async throws -> TimeEntry {
        guard let a = assignments.first(where: { $0.project.id == projectID }),
              let ta = a.taskAssignments.first(where: { $0.task.id == taskID })
        else { throw HarvestError.server(status: 422, message: "Unknown task") }
        nextID += 1
        let entry = TimeEntry(
            id: nextID, spentDate: spentDate,
            project: NamedRef(id: a.project.id, name: a.project.name), task: ta.task, client: a.client,
            hours: 0, hoursWithoutTimer: 0, notes: notes, isRunning: true, timerStartedAt: .now
        )
        entries.append(entry)
        return entry
    }

    public func createEntry(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?, hours: Double, times: ClockTimes?) async throws -> TimeEntry {
        guard let a = assignments.first(where: { $0.project.id == projectID }),
              let ta = a.taskAssignments.first(where: { $0.task.id == taskID })
        else { throw HarvestError.server(status: 422, message: "Unknown task") }
        nextID += 1
        let entry = TimeEntry(
            id: nextID, spentDate: spentDate,
            project: NamedRef(id: a.project.id, name: a.project.name), task: ta.task, client: a.client,
            hours: hours, hoursWithoutTimer: hours, notes: notes, isRunning: false, timerStartedAt: nil
        )
        entries.append(entry)
        return entry
    }

    public func restartTimer(id: Int) async throws -> TimeEntry {
        try replace(id) { e in
            TimeEntry(id: e.id, spentDate: e.spentDate, project: e.project, task: e.task, client: e.client,
                      hours: e.hours, hoursWithoutTimer: e.hours, notes: e.notes, isRunning: true,
                      timerStartedAt: .now, createdAt: e.createdAt)
        }
    }

    public func stopTimer(id: Int) async throws -> TimeEntry {
        try replace(id) { e in
            TimeEntry(id: e.id, spentDate: e.spentDate, project: e.project, task: e.task, client: e.client,
                      hours: (e.elapsed() / 3600).rounded(toPlaces: 2), notes: e.notes, createdAt: e.createdAt)
        }
    }

    public func updateNotes(id: Int, notes: String) async throws -> TimeEntry {
        try replace(id) { e in
            TimeEntry(id: e.id, spentDate: e.spentDate, project: e.project, task: e.task, client: e.client,
                      hours: e.hours, hoursWithoutTimer: e.hoursWithoutTimer, notes: notes, isRunning: e.isRunning,
                      timerStartedAt: e.timerStartedAt, createdAt: e.createdAt)
        }
    }

    public func updateEntry(id: Int, projectID: Int, taskID: Int, notes: String, hours: Double?, times: ClockTimes?) async throws -> TimeEntry {
        guard let a = assignments.first(where: { $0.project.id == projectID }),
              let ta = a.taskAssignments.first(where: { $0.task.id == taskID })
        else { throw HarvestError.server(status: 422, message: "Unknown task") }
        return try replace(id) { e in
            TimeEntry(id: e.id, spentDate: e.spentDate, project: NamedRef(id: a.project.id, name: a.project.name),
                      task: ta.task, client: a.client, hours: hours ?? e.hours, hoursWithoutTimer: e.hoursWithoutTimer,
                      notes: notes, isRunning: e.isRunning, timerStartedAt: e.timerStartedAt, createdAt: e.createdAt)
        }
    }

    public func deleteEntry(id: Int) async throws {
        entries.removeAll { $0.id == id }
    }

    private func replace(_ id: Int, _ transform: (TimeEntry) -> TimeEntry) throws -> TimeEntry {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw HarvestError.server(status: 404, message: "Entry not found")
        }
        entries[index] = transform(entries[index])
        return entries[index]
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
