import HarvestKit
import SwiftUI

/// How the Favorites section looks, picked in the window's ⋯ menu.
enum FavoritesStyle: String, CaseIterable, Identifiable {
    /// Two-line tiles on a soft orange panel (the original).
    case panel
    /// One quiet row each: star, name, today's time.
    case list

    static let key = "favoritesStyle"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .panel: return "Panel"
        case .list: return "List"
        }
    }
}

/// Shared bits for a favorite: running state, start/pause, and drag to reorder.
private struct FavoriteChrome: ViewModifier {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    @Binding var picksIcon: Bool
    @State private var isDropTarget = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .modifier(FavoriteIconPopover(key: task.key, isPresented: $picksIcon))
            .onTapGesture { Task { await tracker.toggle(task) } }
            .draggable(task.key.description)
            .dropDestination(for: String.self) { items, _ in
                guard let key = items.first.flatMap(TaskKey.init) else { return false }
                withAnimation(.snappy(duration: 0.2)) { tracker.favorites.place(key, before: task.key) }
                return true
            } isTargeted: { targeted in withAnimation(.snappy(duration: 0.15)) { isDropTarget = targeted } }
            .opacity(isDropTarget ? 0.6 : 1)
            .contextMenu {
                Button("Start or Pause Timer", systemImage: "playpause") { Task { await tracker.toggle(task) } }
                Button("Choose Icon…", systemImage: "face.smiling") { picksIcon = true }
                Button("Remove from Favorites", systemImage: "star.slash") { tracker.favorites.toggle(task.key) }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await tracker.toggle(task) } }
    }
}

extension TimeTracker {
    /// Shows the state you just asked for while Harvest confirms it.
    func isShownRunning(_ task: TrackableTask) -> Bool {
        let running = self.running?.key == task.key
        return busyKey == task.key ? !running : running
    }
}

// MARK: List

struct FavoritesListView: View {
    @Environment(TimeTracker.self) private var tracker
    let tasks: [TrackableTask]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 { Divider().padding(.leading, 30) }
                    FavoriteRow(task: task, seconds: tracker.secondsToday(for: task, at: context.date))
                }
            }
        }
    }
}

private struct FavoriteRow: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let seconds: TimeInterval
    @State private var isHovered = false
    @State private var picksIcon = false

    var body: some View {
        let running = tracker.isShownRunning(task)
        let (_, project) = task.projectNameParts
        HStack(spacing: 10) {
            Group {
                if let icon = FavoriteIcons.shared.icon(for: task.key) {
                    FavoriteIconView(icon: icon, size: 15)
                } else {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.harvestOrange)
                }
            }
            .frame(width: 22)
            .onTapGesture { picksIcon = true }
            .help("Choose an icon")
            Text(project).font(.system(size: 13, weight: running ? .semibold : .regular)).lineLimit(1)
            Text(task.task.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if running || isHovered {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.harvestOrange)
            }
            if running || seconds > 0 {
                Text(TimeFormat.hoursMinutes(seconds))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(running ? AnyShapeStyle(Color.harvestOrange) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
        )
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .modifier(FavoriteChrome(task: task, picksIcon: $picksIcon))
    }
}
