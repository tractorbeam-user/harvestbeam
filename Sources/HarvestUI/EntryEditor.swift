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
    private var hoursEmpty: Bool { hours.trimmingCharacters(in: .whitespaces).isEmpty }
    private var startsTimer: Bool { entry == nil && isToday && hoursEmpty }
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
                        .help(isTimerRunning ? "Change the time to stop the timer at it"
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
                    .disabled(isSaving || taskKey == nil || (!startsTimer && !isTimerRunning && !hoursEmpty && parsedHours == nil))
            }
            .padding(14)
        }
        .frame(width: 340)
        .dimsWindow()
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

    /// Click and type to filter projects, like Harvest's picker; arrows and
    /// Return pick one.
    private var projectMenu: some View {
        ProjectPicker(groups: projectGroups, selected: selectedTask, label: projectLabel) { task in
            projectID = task.project.id
            if taskKey?.projectID != task.project.id { taskKey = tasks(in: task.project.id).first?.key }
        }
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
                // Empty hours on another day adds a 0:00 entry to fill in later.
                await tracker.addEntry(task: task, on: day, notes: notes, hours: startsTimer ? nil : (parsedHours ?? 0))
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

/// Harvest-style project combo box: shows the chosen project; click it and
/// type to filter by project, code or client, grouped by client.
private struct ProjectPicker: View {
    let groups: [(name: String, projects: [TrackableTask])]
    let selected: TrackableTask?
    let label: (TrackableTask) -> String
    let onPick: (TrackableTask) -> Void

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var matches: [(client: String, task: TrackableTask)] {
        let words = query.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(separator: " ").map(String.init)
        var result: [(client: String, task: TrackableTask)] = []
        for group in groups {
            for task in group.projects {
                let haystack = (label(task) + " " + group.name).lowercased().folding(options: .diacriticInsensitive, locale: nil)
                if words.allSatisfy(haystack.contains) { result.append((group.name, task)) }
            }
        }
        return result
    }

    var body: some View {
        let matches = matches
        VStack(spacing: 0) {
            HStack {
                ZStack(alignment: .leading) {
                    TextField("Project", text: $query, prompt: Text(focused ? "Search projects…" : ""))
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, max(matches.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                        .onSubmit { if matches.indices.contains(highlighted) { pick(matches[highlighted].task) } }
                        .onExitCommand { query = ""; focused = false }
                    if !focused && query.isEmpty {
                        Text(selected.map(label) ?? "Choose a project…")
                            .foregroundStyle(selected == nil ? Color.secondary : Color.primary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(focused ? 180 : 0))
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .onChange(of: query) { highlighted = 0 }

            if focused {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if matches.isEmpty {
                                Text("No projects match “\(query)”")
                                    .font(.system(size: 12)).foregroundStyle(Color.secondary)
                                    .padding(10)
                            }
                            ForEach(Array(matches.enumerated()), id: \.element.task.project.id) { index, match in
                                if index == 0 || matches[index - 1].client != match.client {
                                    Text(match.client)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.top, index == 0 ? 6 : 10)
                                        .padding(.bottom, 2)
                                }
                                Text(label(match.task))
                                    .font(.system(size: 13))
                                    .foregroundStyle(index == highlighted ? Color.white : Color.primary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 5)
                                        .fill(index == highlighted ? Color.harvestOrange : Color.clear))
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture { pick(match.task) }
                                    .onHover { if $0 { highlighted = index } }
                                    .id(index)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    // A ScrollView has no height of its own inside a popover, so
                    // size it to the rows (about 26pt each, plus client headers).
                    .frame(height: listHeight(matches))
                    .onChange(of: highlighted) { _, index in proxy.scrollTo(index) }
                }
            }
        }
    }

    private func listHeight(_ matches: [(client: String, task: TrackableTask)]) -> CGFloat {
        guard !matches.isEmpty else { return 36 }
        let clients = Set(matches.map(\.client)).count
        return min(240, CGFloat(matches.count) * 27 + CGFloat(clients) * 24 + 8)
    }

    private func pick(_ task: TrackableTask) {
        onPick(task)
        query = ""
        focused = false
    }
}
