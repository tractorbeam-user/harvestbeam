import HarvestKit
import SwiftUI

/// One project/task as a compact two-line tile: project, then task. Click or
/// tap anywhere on it to start its timer (or pause it if it's running).
/// Outside Favorites a star shows on hover to pin it.
struct TaskTile: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    var isSelected = false
    /// Off in Favorites, where every tile is already starred.
    var showsStar = true
    /// Set in Suggested: an × on hover removes the task from that list.
    var onRemove: (() -> Void)?
    /// In Favorites, dropping another tile on this one puts it just before.
    var acceptsDrops = false
    @State private var isDropTarget = false
    @State private var isHovered = false

    private var isBusy: Bool { tracker.busyKey == task.key }
    /// Shows the state you just asked for while Harvest confirms it, instead
    /// of a spinner.
    private var isRunning: Bool {
        let running = tracker.running?.key == task.key
        return isBusy ? !running : running
    }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        // Not a Button: on macOS a button keeps the mouse press to itself, so
        // the tile could never be dragged. A tap starts or pauses instead.
        content
            .modifier(TileChrome(isRunning: isRunning, isSelected: isSelected, isHovered: isHovered))
            .onTapGesture { Task { await tracker.toggle(task) } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Task { await tracker.toggle(task) } }
        // Drag any tile into Favorites; in Favorites, drop on a tile to put
        // the dragged one before it.
        .draggable(task.key.description) {
            Text(task.projectNameParts.name + " · " + task.task.name)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(Color.harvestOrange))
                .foregroundStyle(.white)
        }
        .dropDestination(for: String.self) { items, _ in
            guard acceptsDrops, let key = items.first.flatMap(TaskKey.init) else { return false }
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.place(key, before: task.key) }
            return true
        } isTargeted: { targeted in
            withAnimation(.snappy(duration: 0.15)) { isDropTarget = acceptsDrops && targeted }
        }
        // While a tile is dragged over this one, an insertion line in the gap
        // before it shows where it'll land, and this tile makes a little room.
        .offset(x: isDropTarget ? 6 : 0)
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule()
                    .fill(Color.harvestOrange)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .offset(x: -(Metrics.spacing / 2) - 1.5)
                    .transition(.opacity)
            }
        }
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .contextMenu {
            Button(isRunning ? "Pause Timer" : "Start Timer", systemImage: isRunning ? "pause.fill" : "play.fill") {
                Task { await tracker.toggle(task) }
            }
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                tracker.favorites.toggle(task.key)
            }
            if let onRemove {
                Button("Remove from Suggested", systemImage: "xmark", action: onRemove)
            }
        }
        .help([task.client?.name, task.projectCode].compactMap { $0 }.joined(separator: " · "))
        .accessibilityLabel("\(task.project.name), \(task.task.name), \(task.client?.name ?? "")")
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts a timer")
    }

    private var content: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                let (code, name) = task.projectNameParts
                if let code {
                    Text(code)
                        .font(.system(size: codeFont, weight: .medium).monospaced())
                        .opacity(isRunning ? 0.82 : 0.5)
                        .padding(.bottom, 1)
                }
                // Hover slides a name that doesn't fit across to show the rest.
                MarqueeText(text: name, isActive: isHovered)
                    .font(.system(size: titleFont, weight: .semibold))
                MarqueeText(text: task.task.name, isActive: isHovered)
                    .font(.system(size: subtitleFont))
                    .opacity(isRunning ? 0.82 : 0.6)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let onRemove, isHovered, !isRunning {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove from Suggested")
                .accessibilityLabel("Remove \(task.task.name) from Suggested")
            }
            if showsStar && (isHovered || isFavorite) { favoriteButton }
            actionIndicator
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Metrics.tileHeight, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(isRunning ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }

    @ViewBuilder private var actionIndicator: some View {
        Group {
            if isRunning {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.harvestOrange)
                    .background(Circle().fill(.white).frame(width: indicatorSize, height: indicatorSize))
            } else {
                Image(systemName: "play.fill")
                    .foregroundStyle(isHovered || isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .background(Circle().fill(isHovered || isSelected ? Color.harvestOrange : Color.orangeSoft).frame(width: indicatorSize, height: indicatorSize))
            }
        }
        .font(.system(size: 9, weight: .bold))
        .frame(width: indicatorSize, height: indicatorSize)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var favoriteButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.toggle(task.key) }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(starStyle)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(task.task.name) from Favorites" : "Add \(task.task.name) to Favorites")
    }

    /// White on the orange running tile, orange when starred, faint otherwise.
    private var starStyle: AnyShapeStyle {
        if isRunning { return AnyShapeStyle(.white.opacity(isFavorite ? 1 : 0.7)) }
        return isFavorite ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary)
    }

    #if os(macOS)
    private let codeFont: CGFloat = 10.5
    private let titleFont: CGFloat = 12.5
    private let subtitleFont: CGFloat = 11.5
    private let indicatorSize: CGFloat = 28
    #else
    private let codeFont: CGFloat = 12
    private let titleFont: CGFloat = 15
    private let subtitleFont: CGFloat = 14
    private let indicatorSize: CGFloat = 30
    #endif
}

private struct TileChrome: ViewModifier {
    let isRunning: Bool
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        // Flat, like the landing page: a hairline, no shadow. Hover only
        // darkens the line a touch.
        let shape = RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
        content
            .background(shape.fill(isRunning ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(Color.tileBackground)))
            .overlay(shape.strokeBorder(border, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var border: Color {
        if isSelected { return .harvestOrange }
        if isRunning { return .clear }
        return isHovered ? Color.primary.opacity(0.18) : .hairline
    }
}
