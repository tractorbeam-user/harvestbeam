import Foundation

/// An in-memory Harvest with a few weeks of believable history, for trying the
/// UI without an account and for SwiftUI previews.
public actor DemoHarvestService: HarvestService {
    private var assignments: [ProjectAssignment]
    private var entries: [TimeEntry]
    private var nextID = 10_000

    public init(now: Date = .now) {
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
        ]

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
                generated.append(TimeEntry(
                    id: id, spentDate: day,
                    project: NamedRef(id: projectID, name: projectNames[projectID]!), task: task, client: client,
                    hours: (random() * 3 + 0.25).rounded(toPlaces: 2),
                    createdAt: stamp, updatedAt: stamp
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
        entries = generated
    }

    public func currentUser() async throws -> HarvestUser {
        HarvestUser(id: 1, firstName: "Demo", lastName: "User", email: "demo@example.com")
    }

    public func company() async throws -> Company {
        Company(baseUri: "https://example.harvestapp.com", name: "Tractorbeam (demo)", weekStartDay: "Monday")
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

    public func updateEntry(id: Int, projectID: Int, taskID: Int, notes: String, hours: Double?) async throws -> TimeEntry {
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
