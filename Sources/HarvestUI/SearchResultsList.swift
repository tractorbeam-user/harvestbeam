import HarvestKit
import SwiftUI

/// Search in two steps, like Harvest's own pickers: first the matching
/// projects under client headings, then the picked project's tasks.
struct SearchResultsList: View {
    @Environment(TimeTracker.self) private var tracker
    #if os(macOS)
    private let headerFont: CGFloat = 13
    #else
    private let headerFont: CGFloat = 16
    #endif
    /// One task per project (standing in for it), or the picked project's tasks.
    let tasks: [TrackableTask]
    let selection: TaskKey?
    let query: String
    let pickedProject: Int?
    let pick: (TrackableTask) -> Void
    let back: () -> Void

    var body: some View {
        if tasks.isEmpty {
            Text("No projects match “\(query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                if pickedProject != nil, let first = tasks.first {
                    Button(action: back) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(first.client?.name ?? "No client")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(projectLabel(first)).font(.system(size: headerFont, weight: .semibold))
                            }
                            .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Back to projects (esc)")
                    .padding(.bottom, 4)

                    ForEach(tasks) { task in
                        ResultRow(task: task, title: Text(task.task.name), isSelected: selection == task.key, isProject: false) { pick(task) }
                            .id(task.key)
                    }
                } else {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        if index == 0 || tasks[index - 1].client?.id != task.client?.id {
                            Text(task.client?.name ?? "No client")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 3)
                        }
                        ResultRow(task: task, title: Text(projectLabel(task)), isSelected: selection == task.key, isProject: true) { pick(task) }
                            .id(task.key)
                    }
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .opacity(isSelected || isHovered || (isRunning && !isProject) ? 1 : 0)
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
