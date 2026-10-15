import HarvestKit
import SwiftUI

/// Edit a time entry's task, notes and hours, like Harvest's Edit Entry sheet.
struct EntryEditor: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry

    @State private var taskKey: TaskKey
    @State private var notes: String
    @State private var hours: String
    @State private var isSaving = false

    init(entry: TimeEntry) {
        self.entry = entry
        _taskKey = State(initialValue: entry.key)
        _notes = State(initialValue: entry.notes ?? "")
        _hours = State(initialValue: TimeFormat.hoursMinutes(entry.elapsed()))
    }

    private var parsedHours: Double? { Self.parseHours(hours) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Entry")
                .font(.headline)
                .frame(maxWidth: .infinity)

            Picker("Task", selection: $taskKey) {
                ForEach(groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.tasks) { task in
                            Text(label(for: task)).tag(task.key)
                        }
                    }
                }
            }

            TextField("Notes", text: $notes, prompt: Text("Notes (optional)"), axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Hours", text: $hours, prompt: Text("0:00"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .disabled(entry.isRunning)
                    .monospacedDigit()
                Text(entry.isRunning ? "Pause the timer to change hours" : "h:mm or decimal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Entry") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || (!entry.isRunning && parsedHours == nil))
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var groups: [(name: String, tasks: [TrackableTask])] {
        var tasks = tracker.tasks
        // Keep the entry's own task selectable even if it's no longer assigned.
        if !tasks.contains(where: { $0.key == entry.key }) { tasks.append(tracker.task(for: entry)) }
        let byClient = Dictionary(grouping: tasks) { $0.client?.name ?? "No client" }
        return byClient.keys.sorted().map { name in
            (name, byClient[name]!.sorted { ($0.project.name, $0.task.name) < ($1.project.name, $1.task.name) })
        }
    }

    private func label(for task: TrackableTask) -> String {
        let project = task.projectCode.map { "[\($0)] \(task.project.name)" } ?? task.project.name
        return "\(project) · \(task.task.name)"
    }

    private func save() {
        guard let task = tracker.tasks(for: [taskKey]).first ?? (taskKey == entry.key ? tracker.task(for: entry) : nil) else { return }
        isSaving = true
        Task {
            await tracker.updateEntry(entry, task: task, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), hours: parsedHours)
            isSaving = false
            dismiss()
        }
    }

    /// "1:30" → 1.5, "1.25" → 1.25, "45m" → 0.75.
    static func parseHours(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2, let h = Double(parts[0]), let m = Double(parts[1]), m < 60 else { return nil }
            return h + m / 60
        }
        if trimmed.hasSuffix("m"), let m = Double(trimmed.dropLast()) { return m / 60 }
        return Double(trimmed.replacingOccurrences(of: "h", with: ""))
    }
}

/// Add time to a day, like Harvest's New Time Entry sheet: pick the project,
/// then its task. Today with no hours starts a timer; otherwise it logs them.
struct NewEntryEditor: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let day: LocalDate

    @State private var projectID: Int?
    @State private var taskKey: TaskKey?
    @State private var notes = ""
    @State private var hours = ""
    @State private var isSaving = false

    private var isToday: Bool { day == LocalDate() }
    private var parsedHours: Double? { EntryEditor.parseHours(hours) }
    private var startsTimer: Bool { isToday && hours.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isToday ? "New Time Entry" : "New Entry · \(day.dayTitle(today: LocalDate()))")
                .font(.headline)
                .frame(maxWidth: .infinity)

            Picker("Project", selection: $projectID) {
                Text("Choose a project…").tag(Int?.none)
                ForEach(projectGroups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.projects, id: \.project.id) { task in
                            Text(task.projectCode.map { "[\($0)] \(task.project.name)" } ?? task.project.name)
                                .tag(Int?.some(task.project.id))
                        }
                    }
                }
            }
            .onChange(of: projectID) { _, id in
                // Keep the task if it belongs to the new project, else pick the first.
                if taskKey?.projectID != id { taskKey = tasks(in: id).first?.key }
            }

            Picker("Task", selection: $taskKey) {
                ForEach(tasks(in: projectID)) { task in
                    Text(task.task.name).tag(TaskKey?.some(task.key))
                }
            }
            .disabled(projectID == nil)

            TextField("Notes", text: $notes, prompt: Text("Notes (optional)"), axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)

            HStack {
                TextField("Hours", text: $hours, prompt: Text("0:00"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .monospacedDigit()
                Text(isToday ? "Leave empty to start a timer" : "h:mm or decimal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(startsTimer ? "Start Timer" : "Save Entry") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || taskKey == nil || (!startsTimer && parsedHours == nil))
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            // Start from the most recently used task.
            if let recent = tracker.recentTasks.first ?? tracker.favoriteTasks.first {
                projectID = recent.project.id
                taskKey = recent.key
            }
        }
    }

    /// One representative task per project, grouped by client.
    private var projectGroups: [(name: String, projects: [TrackableTask])] {
        var seen = Set<Int>()
        let projects = tracker.tasks.filter { seen.insert($0.project.id).inserted }
        let byClient = Dictionary(grouping: projects) { $0.client?.name ?? "No client" }
        return byClient.keys.sorted().map { name in
            (name, byClient[name]!.sorted { $0.project.name < $1.project.name })
        }
    }

    private func tasks(in projectID: Int?) -> [TrackableTask] {
        guard let projectID else { return [] }
        return tracker.tasks.filter { $0.project.id == projectID }.sorted { $0.task.name < $1.task.name }
    }

    private func save() {
        guard let taskKey, let task = tracker.tasks(for: [taskKey]).first else { return }
        isSaving = true
        Task {
            await tracker.addEntry(task: task, on: day, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                   hours: startsTimer ? nil : parsedHours)
            isSaving = false
            dismiss()
        }
    }
}
