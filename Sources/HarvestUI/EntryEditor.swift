import HarvestKit
import SwiftUI

enum EntryEditor {
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

/// Add or edit time, laid out like Harvest's New Time Entry popover: a star,
/// project over task, notes beside hours. A new entry for today with no hours
/// starts a timer; otherwise it logs the hours.
struct NewEntryEditor: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let day: LocalDate
    /// Set when editing an existing entry.
    var entry: TimeEntry?
    @FocusState private var hoursFocused: Bool

    @State private var projectID: Int?
    @State private var taskKey: TaskKey?
    @State private var notes = ""
    @State private var hours = ""
    @State private var isSaving = false
    @State private var isFavoriteHovered = false

    private var isToday: Bool { day == LocalDate() }
    private var parsedHours: Double? { EntryEditor.parseHours(hours) }
    private var startsTimer: Bool { entry == nil && isToday && hours.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isTimerRunning: Bool { entry?.isRunning ?? false }
    private var selectedTask: TrackableTask? {
        guard let taskKey else { return nil }
        if let task = tracker.tasks(for: [taskKey]).first { return task }
        // The entry's own task may no longer be assigned to you.
        if let entry, entry.key == taskKey { return tracker.task(for: entry) }
        return nil
    }
    private var isFavorite: Bool { taskKey.map(tracker.favorites.contains) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            Text((entry == nil ? "New Time Entry" : "Edit Time Entry") + (isToday ? "" : " · \(day.dayTitle(today: LocalDate()))"))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 14)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    projectMenu.hoverHighlight(corners: [.topLeft, .topRight])
                    Divider().padding(.leading, 10)
                    taskMenu.hoverHighlight(corners: [.bottomLeft, .bottomRight])
                }
                .background(fieldBackground)

                HStack(alignment: .top, spacing: 10) {
                    TextField("Notes", text: $notes, prompt: Text("Notes (optional)"), axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                        .background(fieldBackground)
                        .hoverOutline()
                    // Big and centered so the time fills its box, like Harvest's.
                    TextField("Hours", text: $hours, prompt: Text("0:00"))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 22, weight: .light).monospacedDigit())
                        .padding(.horizontal, 10)
                        .frame(width: 84, height: 50)
                        .background(fieldBackground)
                        .hoverOutline()
                        .focused($hoursFocused)
                        .disabled(isTimerRunning)
                        .help(isTimerRunning ? "Pause the timer to change hours"
                              : startsTimer || (entry == nil && isToday) ? "h:mm or decimal. Leave empty to start a timer." : "h:mm or decimal")
                }
            }
            .padding(.horizontal, 14)

            HStack(spacing: 8) {
                // Favorite sits opposite the buttons instead of in a gutter.
                Button {
                    if let taskKey { tracker.favorites.toggle(taskKey) }
                } label: {
                    Label("Favorite", systemImage: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .medium))
                        .fixedSize()
                        .foregroundStyle(isFavorite || isFavoriteHovered ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(Color.secondary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.harvestOrange.opacity(isFavoriteHovered ? 0.1 : 0)))
                }
                .buttonStyle(.plain)
                .onHover { isFavoriteHovered = $0 }
                .padding(.leading, -8)
                .disabled(taskKey == nil)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(PillButtonStyle(prominent: false))
                Button(startsTimer ? "Start Timer" : "Save Entry") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(isSaving || taskKey == nil || (!startsTimer && !isTimerRunning && parsedHours == nil))
            }
            .padding(14)
        }
        .frame(width: 340)
        .presentationBackground(Color.tileBackground)
        // Opened from the bottom bar, which dims its own text; `.primary` would
        // inherit that, so use the real label color.
        .foregroundStyle(Color.primary)
        .onAppear {
            if let entry {
                projectID = entry.key.projectID
                taskKey = entry.key
                notes = entry.notes ?? ""
                hours = TimeFormat.hoursMinutes(entry.elapsed())
                if !entry.isRunning { hoursFocused = true }
            // Start from the most recently used task.
            } else if let recent = tracker.recentTasks.first ?? tracker.favoriteTasks.first {
                projectID = recent.project.id
                taskKey = recent.key
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.panelBackground.opacity(0.5))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
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
        .frame(height: 34)
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
        let notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            if let entry {
                await tracker.updateEntry(entry, task: task, notes: notes, hours: parsedHours)
            } else {
                await tracker.addEntry(task: task, on: day, notes: notes, hours: startsTimer ? nil : parsedHours)
            }
            isSaving = false
            dismiss()
        }
    }
}

/// Rounded buttons for the entry popover: orange for the main action,
/// a quiet tint for the rest.
struct PillButtonStyle: ButtonStyle {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(isHovered && isEnabled ? Color(red: 0.86, green: 0.31, blue: 0) : Color.harvestOrange)
                          : AnyShapeStyle(Color.primary.opacity(isHovered && isEnabled ? 0.12 : 0.07)))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

#if DEBUG
/// For offscreen snapshots of the New Entry popover.
public func debugNewEntryEditor() -> some View { NewEntryEditor(day: LocalDate()) }
#endif

/// Hover feedback for the entry popover's fields and menus.
private struct HoverHighlight: ViewModifier {
    var corners: RectCorners = .all
    var outline = false
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                UnevenRoundedRectangle(cornerRadii: corners.radii(8), style: .continuous)
                    .fill(Color.primary.opacity(!outline && isHovered ? 0.05 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(outline && isHovered ? 0.18 : 0))
            )
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct RectCorners: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorners(rawValue: 1), topRight = RectCorners(rawValue: 2)
    static let bottomLeft = RectCorners(rawValue: 4), bottomRight = RectCorners(rawValue: 8)
    static let all: RectCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    func radii(_ r: CGFloat) -> RectangleCornerRadii {
        RectangleCornerRadii(topLeading: contains(.topLeft) ? r : 0, bottomLeading: contains(.bottomLeft) ? r : 0,
                             bottomTrailing: contains(.bottomRight) ? r : 0, topTrailing: contains(.topRight) ? r : 0)
    }
}

extension View {
    fileprivate func hoverHighlight(corners: RectCorners = .all) -> some View { modifier(HoverHighlight(corners: corners)) }
    fileprivate func hoverOutline() -> some View { modifier(HoverHighlight(outline: true)) }
}
