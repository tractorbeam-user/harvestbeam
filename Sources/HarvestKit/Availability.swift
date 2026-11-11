import Foundation

/// Why new time can't go on a project/task any more: it was archived in
/// Harvest, or you were taken off it. Old entries on it stay as they are.
public struct TaskUnavailability: Hashable, Sendable {
    public enum Kind: Sendable {
        /// Harvest reports the project as archived.
        case projectArchived
        /// The project's still open, but this task was archived or taken off it.
        case taskArchived
        /// Harvest no longer lists it among your assignments at all. Harvest
        /// leaves archived projects out of that list, so this is usually an
        /// archived project, sometimes being taken off one.
        case notAssigned
    }

    public let kind: Kind

    public init(kind: Kind) { self.kind = kind }

    /// Short tag for rows and tiles.
    public var title: String { "Archived" }

    /// One sentence on what happened, one on what to do.
    public var detail: String {
        switch kind {
        case .projectArchived:
            "This project is archived in Harvest, so new time can't be tracked to it. Ask a Harvest admin to restore it if you still need it."
        case .taskArchived:
            "This task is archived or was removed from the project in Harvest, so new time can't be tracked to it. Ask a Harvest admin to add it back if you still need it."
        case .notAssigned:
            "This project is archived in Harvest, or you're no longer assigned to it, so new time can't be tracked to it. Ask a Harvest admin if you still need it."
        }
    }

    /// For hover help: "Archived · can't start: …".
    public var help: String { "Archived in Harvest · can't be started. " + detail }
}

extension ProjectAssignment {
    /// Project/task pairs Harvest still lists but marks inactive: archived
    /// projects, and archived tasks on open ones.
    public static func archivedTasks(from assignments: [ProjectAssignment]) -> [TaskKey: (task: TrackableTask, kind: TaskUnavailability.Kind)] {
        var result: [TaskKey: (task: TrackableTask, kind: TaskUnavailability.Kind)] = [:]
        for a in assignments {
            for ta in a.taskAssignments where !a.isActive || !ta.isActive {
                let task = TrackableTask(
                    project: NamedRef(id: a.project.id, name: a.project.name),
                    projectCode: a.project.code.flatMap { $0.isEmpty ? nil : $0 },
                    client: a.client,
                    task: ta.task
                )
                result[task.key] = (task, a.isActive ? .taskArchived : .projectArchived)
            }
        }
        return result
    }
}

/// Names of starred tasks, kept so a favorite whose project gets archived
/// can still be shown (as archived) after Harvest stops listing it.
struct RememberedTasks {
    private struct Saved: Codable {
        let projectID: Int, projectName: String, projectCode: String?
        let clientID: Int?, clientName: String?
        let taskID: Int, taskName: String
    }

    static let key = "rememberedFavoriteTasks.v1"

    static func load(from defaults: UserDefaults) -> [TaskKey: TrackableTask] {
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return [:] }
        return Dictionary(saved.map { s in
            let client = s.clientID.map { NamedRef(id: $0, name: s.clientName ?? "") }
            let task = TrackableTask(project: NamedRef(id: s.projectID, name: s.projectName), projectCode: s.projectCode,
                                     client: client, task: NamedRef(id: s.taskID, name: s.taskName))
            return (task.key, task)
        }, uniquingKeysWith: { first, _ in first })
    }

    static func save(_ tasks: [TrackableTask], to defaults: UserDefaults) {
        let saved = tasks.map {
            Saved(projectID: $0.project.id, projectName: $0.project.name, projectCode: $0.projectCode,
                  clientID: $0.client?.id, clientName: $0.client?.name, taskID: $0.task.id, taskName: $0.task.name)
        }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
    }
}
