import HarvestKit
import SwiftUI

/// Dense results grouped by client, then project, with one line per task
/// under its project, like Harvest's own project then task pickers. Keyboard selection shows as a solid highlight.
struct SearchResultsList: View {
    @Environment(TimeTracker.self) private var tracker
    #if os(macOS)
    private let projectFont: CGFloat = 13
    #else
    private let projectFont: CGFloat = 16
    #endif
    /// Already grouped by client and project (see `TrackerView.groupedByClient`).
    let tasks: [TrackableTask]
    let selection: TaskKey?
    let query: String

    var body: some View {
        if tasks.isEmpty {
            Text("No tasks match “\(query)”")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    let newClient = index == 0 || tasks[index - 1].client?.id != task.client?.id
                    if newClient {
                        Text(task.client?.name ?? "No client")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, index == 0 ? 2 : 12)
                            .padding(.bottom, 1)
                    }
                    if newClient || tasks[index - 1].project.id != task.project.id {
                        (Text(task.projectCode.map { "[\($0)] " } ?? "").foregroundStyle(.secondary) + Text(task.project.name))
                            .font(.system(size: projectFont, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.top, newClient ? 3 : 8)
                            .padding(.bottom, 1)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ResultRow(task: task, isSelected: selection == task.key)
                        .id(task.key)
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        }
    }
}

private struct ResultRow: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let isSelected: Bool
    @State private var isHovered = false

    private var isRunning: Bool { tracker.running?.key == task.key }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        Button {
            Task { await tracker.toggle(task) }
        } label: {
            HStack(spacing: 6) {
                Text(task.task.name)
                Spacer(minLength: 6)
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                }
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .opacity(isSelected || isHovered || isRunning ? 1 : 0)
                    .frame(width: 14)
            }
            .font(.system(size: rowFont))
            .lineLimit(1)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.leading, 22)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(background))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .contextMenu {
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                tracker.favorites.toggle(task.key)
            }
        }
        .accessibilityLabel("\(task.project.name), \(task.task.name), \(task.client?.name ?? "")")
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts a timer")
    }

    private var secondary: Color {
        isSelected ? .white.opacity(0.8) : .secondary
    }

    private var background: Color {
        if isSelected { return .harvestOrange }
        if isRunning { return Color.harvestOrange.opacity(0.12) }
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
