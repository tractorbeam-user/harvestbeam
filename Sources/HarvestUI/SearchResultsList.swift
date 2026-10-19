import HarvestKit
import SwiftUI

/// Search results: matching projects under client headings. Clicking a
/// project (or Return) opens its tasks right below it; the arrow turns down in
/// place rather than moving to another list.
struct SearchResultsList: View {
    @Environment(TimeTracker.self) private var tracker
    /// Project rows (see `TrackableTask.projectRow`), each followed by its
    /// tasks when it's the open one.
    let tasks: [TrackableTask]
    let selection: TaskKey?
    let query: String
    let pickedProject: Int?
    let pick: (TrackableTask) -> Void

    var body: some View {
        if tasks.isEmpty {
            Text("No projects match “\(query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            let projects = tasks.filter(\.isProjectRow)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(tasks) { task in
                    if task.isProjectRow {
                        let index = projects.firstIndex { $0.key == task.key } ?? 0
                        if index == 0 || projects[index - 1].client?.id != task.client?.id {
                            Text(task.client?.name ?? "No client")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 3)
                        }
                        ResultRow(task: task, title: Text(projectLabel(task)), isSelected: selection == task.key,
                                  isProject: true, isOpen: pickedProject == task.project.id) { pick(task) }
                            .id(task.key)
                    } else {
                        ResultRow(task: task, title: Text(task.task.name), isSelected: selection == task.key,
                                  isProject: false, isOpen: false) { pick(task) }
                            .padding(.leading, 16)
                            .id(task.key)
                            .transition(.opacity)
                    }
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
        }
    }

    private func projectLabel(_ task: TrackableTask) -> String {
        task.projectCode.map { "[\($0)] \(task.project.name)" } ?? task.project.name
    }
}

private struct ResultRow: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let title: Text
    let isSelected: Bool
    /// Project rows open the project's tasks instead of starting a timer.
    let isProject: Bool
    let isOpen: Bool
    let action: () -> Void
    @State private var isHovered = false

    private var isRunning: Bool { tracker.running?.key == task.key }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                title
                Spacer(minLength: 6)
                if !isProject && isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                }
                Image(systemName: isProject ? "chevron.right" : isRunning ? "pause.fill" : "play.fill")
                    .rotationEffect(.degrees(isProject && isOpen ? 90 : 0))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .opacity(isSelected || isHovered || isOpen || (isRunning && !isProject) ? 1 : 0)
                    .frame(width: 14)
            }
            .font(.system(size: rowFont))
            .lineLimit(1)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .contextMenu {
            if !isProject {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                tracker.favorites.toggle(task.key)
            }
            }
        }
        .accessibilityLabel(isProject ? "\(task.project.name), \(task.client?.name ?? "")" : task.task.name)
        .accessibilityHint(isProject ? "Shows this project's tasks" : isRunning ? "Pauses the timer" : "Starts a timer")
    }

    private var secondary: Color {
        isSelected ? .white.opacity(0.8) : .secondary
    }

    private var background: Color {
        if isSelected { return .harvestOrange }
        if isRunning && !isProject { return Color.harvestOrange.opacity(0.12) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }

    #if os(macOS)
    private let rowHeight: CGFloat = 26
    private let rowFont: CGFloat = 13
    #else
    private let rowHeight: CGFloat = 40
    private let rowFont: CGFloat = 16
    #endif
}
