import HarvestKit
import SwiftUI

/// How the Favorites section looks, picked in the window's ⋯ menu.
enum FavoritesStyle: String, CaseIterable, Identifiable {
    /// Two-line tiles on a soft orange panel (the original).
    case panel
    /// One quiet row each: star, name, today's time.
    case list
    /// A wrap of small pills under the ask box.
    case chips
    /// Large tiles with today's time on each.
    case tiles

    static let key = "favoritesStyle"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .panel: return "Panel"
        case .list: return "List"
        case .chips: return "Chips"
        case .tiles: return "Big Tiles"
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

// MARK: Chips

struct FavoritesChipsView: View {
    @Environment(TimeTracker.self) private var tracker
    let tasks: [TrackableTask]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tasks) { task in
                // Two favorites in one project would read the same; add the task.
                let name = task.projectNameParts.name
                let shared = tasks.filter { $0.projectNameParts.name == name }.count > 1
                FavoriteChip(task: task, label: shared ? name + " · " + task.task.name : name)
            }
        }
    }
}

private struct FavoriteChip: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let label: String
    @State private var isHovered = false
    @State private var picksIcon = false

    var body: some View {
        let running = tracker.isShownRunning(task)
        HStack(spacing: 5) {
            if running { Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold)) }
            if let icon = FavoriteIcons.shared.icon(for: task.key) {
                FavoriteIconView(icon: icon, size: 12, onOrange: running)
            }
            Text(label).lineLimit(1)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .contentShape(Capsule())
        .foregroundStyle(running ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            Capsule().fill(running ? AnyShapeStyle(Color.harvestOrange)
                           : AnyShapeStyle(Color.primary.opacity(isHovered ? 0.08 : 0.0)))
        )
        .overlay(Capsule().strokeBorder(running ? Color.clear : Color.primary.opacity(0.15)))
        .help(task.projectNameParts.name + " · " + task.task.name)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        // Room around the pill so dragging's clip doesn't shave its ends.
        .padding(.horizontal, 3)
        .modifier(FavoriteChrome(task: task, picksIcon: $picksIcon))
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

// MARK: Big tiles

struct FavoritesTilesView: View {
    @Environment(TimeTracker.self) private var tracker
    let tasks: [TrackableTask]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(tasks) { task in
                    BigTile(task: task, seconds: tracker.secondsToday(for: task, at: context.date))
                }
            }
        }
    }
}
