import Foundation

/// A `{ "id": …, "name": … }` reference as Harvest embeds it in most objects.
public struct NamedRef: Codable, Hashable, Sendable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// Identifies something you can track time against: a task within a project.
public struct TaskKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let projectID: Int
    public let taskID: Int

    public init(projectID: Int, taskID: Int) {
        self.projectID = projectID
        self.taskID = taskID
    }

    public init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 2, let p = Int(parts[0]), let t = Int(parts[1]) else { return nil }
        self.init(projectID: p, taskID: t)
    }

    public var description: String { "\(projectID):\(taskID)" }
}

/// A project + task pair the signed-in user is assigned to.
public struct TrackableTask: Identifiable, Hashable, Sendable {
    public let project: NamedRef
    public let projectCode: String?
    public let client: NamedRef?
    public let task: NamedRef

    public init(project: NamedRef, projectCode: String? = nil, client: NamedRef?, task: NamedRef) {
        self.project = project
        self.projectCode = projectCode
        self.client = client
        self.task = task
    }

    public var key: TaskKey { TaskKey(projectID: project.id, taskID: task.id) }
    public var id: TaskKey { key }

    /// "Website Redesign · Acme Co"
    public var subtitle: String {
        [project.name, client?.name].compactMap { $0 }.joined(separator: " · ")
    }
}

public struct HarvestUser: Codable, Sendable, Equatable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public let email: String

    public init(id: Int, firstName: String, lastName: String, email: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
    }
}

public struct Company: Codable, Sendable, Equatable {
    /// e.g. https://acme.harvestapp.com
    public let baseUri: String
    public let name: String
    public let wantsTimestampTimers: Bool?
    /// "Monday", "Sunday" or "Saturday".
    public let weekStartDay: String?

    public init(baseUri: String, name: String, wantsTimestampTimers: Bool? = false, weekStartDay: String? = "Monday") {
        self.baseUri = baseUri
        self.name = name
        self.wantsTimestampTimers = wantsTimestampTimers
        self.weekStartDay = weekStartDay
    }

    /// `Calendar`-style weekday the account's weeks start on (2 = Monday).
    public var firstWeekday: Int {
        switch weekStartDay?.lowercased() {
        case "sunday": return 1
        case "saturday": return 7
        default: return 2
        }
    }
}

public struct HarvestAccount: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let product: String

    public init(id: Int, name: String, product: String = "harvest") {
        self.id = id
        self.name = name
        self.product = product
    }
}

public struct ProjectAssignment: Codable, Sendable {
    public struct Project: Codable, Sendable {
        public let id: Int
        public let name: String
        public let code: String?

        public init(id: Int, name: String, code: String? = nil) {
            self.id = id
            self.name = name
            self.code = code
        }
    }

    public struct TaskAssignment: Codable, Sendable {
        public let id: Int
        public let isActive: Bool
        public let task: NamedRef

        public init(id: Int, isActive: Bool = true, task: NamedRef) {
            self.id = id
            self.isActive = isActive
            self.task = task
        }
    }

    public let id: Int
    public let isActive: Bool
    public let project: Project
    public let client: NamedRef?
    public let taskAssignments: [TaskAssignment]

    public init(id: Int, isActive: Bool = true, project: Project, client: NamedRef?, taskAssignments: [TaskAssignment]) {
        self.id = id
        self.isActive = isActive
        self.project = project
        self.client = client
        self.taskAssignments = taskAssignments
    }

    /// Flattens assignments into one row per active project/task pair.
    public static func trackableTasks(from assignments: [ProjectAssignment]) -> [TrackableTask] {
        assignments
            .filter(\.isActive)
            .flatMap { a in
                a.taskAssignments.filter(\.isActive).map { ta in
                    TrackableTask(
                        project: NamedRef(id: a.project.id, name: a.project.name),
                        projectCode: a.project.code.flatMap { $0.isEmpty ? nil : $0 },
                        client: a.client,
                        task: ta.task
                    )
                }
            }
    }
}

public struct TimeEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let spentDate: LocalDate
    public let project: NamedRef
    public let task: NamedRef
    public let client: NamedRef?
    public let hours: Double
    public let hoursWithoutTimer: Double?
    public let notes: String?
    public let isRunning: Bool
    public let timerStartedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: Int, spentDate: LocalDate, project: NamedRef, task: NamedRef, client: NamedRef?,
        hours: Double, hoursWithoutTimer: Double? = nil, notes: String? = nil, isRunning: Bool = false,
        timerStartedAt: Date? = nil, createdAt: Date = .now, updatedAt: Date = .now
    ) {
        self.id = id
        self.spentDate = spentDate
        self.project = project
        self.task = task
        self.client = client
        self.hours = hours
        self.hoursWithoutTimer = hoursWithoutTimer
        self.notes = notes
        self.isRunning = isRunning
        self.timerStartedAt = timerStartedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var key: TaskKey { TaskKey(projectID: project.id, taskID: task.id) }

    /// Seconds tracked, counting a running timer up to `now`.
    public func elapsed(at now: Date = .now) -> TimeInterval {
        guard isRunning, let started = timerStartedAt else { return hours * 3600 }
        return (hoursWithoutTimer ?? 0) * 3600 + max(0, now.timeIntervalSince(started))
    }
}
