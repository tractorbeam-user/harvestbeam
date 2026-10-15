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

/// Add time to a day, laid out like Harvest's New Time Entry popover: a star,
/// project over task, notes beside hours. Today with no hours starts a timer;
/// otherwise it logs the hours.
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
    private var selectedTask: TrackableTask? { taskKey.flatMap { tracker.tasks(for: [$0]).first } }
    private var isFavorite: Bool { taskKey.map(tracker.favorites.contains) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Text(isToday ? "New Time Entry" : "New Time Entry · \(day.dayTitle(today: LocalDate()))")
                .font(.system(size: 13))
                .padding(.vertical, 10)
            Divider()

            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    Button {
                        if let taskKey { tracker.favorites.toggle(taskKey) }
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(isFavorite ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)
                    .disabled(taskKey == nil)
                    .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")

                    VStack(spacing: 0) {
                        projectMenu
                        Divider().padding(.horizontal, 8)
                        taskMenu
                    }
                    .background(fieldBackground)
                }

                HStack(alignment: .top, spacing: 10) {
                    TextField("Notes", text: $notes, prompt: Text("Notes (optional)"), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .frame(minHeight: 44, alignment: .topLeading)
                        .background(fieldBackground)
                    TextField("Hours", text: $hours, prompt: Text("0:00"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 17).monospacedDigit())
                        .padding(8)
                        .frame(width: 76, height: 44)
                        .background(fieldBackground)
                        .help(isToday ? "h:mm or decimal. Leave empty to start a timer." : "h:mm or decimal")
                }
                .padding(.leading, 23)
            }
            .padding(14)

            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(startsTimer ? "Start" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.19, green: 0.66, blue: 0.29))
                    .disabled(isSaving || taskKey == nil || (!startsTimer && parsedHours == nil))
            }
            .controlSize(.large)
            .padding(12)
        }
        .frame(width: 340)
        // Opened from the bottom bar, which dims its own text.
        .foregroundStyle(.primary)
        .onAppear {
            // Start from the most recently used task.
            if let recent = tracker.recentTasks.first ?? tracker.favoriteTasks.first {
                projectID = recent.project.id
                taskKey = recent.key
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.tileBackground)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
    }

    private var projectMenu: some View {
        Menu {
            ForEach(projectGroups, id: \.name) { group in
                Section(group.name) {
                    ForEach(group.projects, id: \.project.id) { task in
                        Button(projectLabel(task)) {
                            projectID = task.project.id
                            if taskKey?.projectID != task.project.id { taskKey = tasks(in: task.project.id).first?.key }
                        }
                    }
                }
            }
        } label: {
            menuLabel(selectedTask.map(projectLabel) ?? "Choose a project…", placeholder: selectedTask == nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var taskMenu: some View {
        Menu {
            ForEach(tasks(in: projectID)) { task in
                Button(task.task.name) { taskKey = task.key }
            }
        } label: {
            menuLabel(selectedTask?.task.name ?? "Task", placeholder: selectedTask == nil)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .disabled(projectID == nil)
    }

    private func menuLabel(_ text: String, placeholder: Bool) -> some View {
        HStack {
            Text(text)
                .lineLimit(1)
                .foregroundStyle(placeholder ? .secondary : .primary)
            Spacer(minLength: 6)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    private func projectLabel(_ task: TrackableTask) -> String {
        task.projectCode.map { "[\($0)] \(task.project.name)" } ?? task.project.name
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
        guard let task = selectedTask else { return }
        isSaving = true
        Task {
            await tracker.addEntry(task: task, on: day, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                                   hours: startsTimer ? nil : parsedHours)
            isSaving = false
            dismiss()
        }
    }
}
