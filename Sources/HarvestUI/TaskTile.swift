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
    /// Dropping another tile on this one puts it just before, in the same
    /// section. Returns whether the drop was taken.
    var dropBefore: ((TaskKey) -> Bool)?
    /// Set in Favorites: the launcher and icon-row looks.
    var style: FavoritesStyle = .classic
    /// Set in a group's panel, for "Remove from <group>".
    var groupID: String?
    @State private var isDropTarget = false
    @AppStorage(TileText.key) private var tileTextRaw = TileText.entry.rawValue
    @State private var isHovered = false
    /// The client's name, shown after the pointer rests on the tile. A
    /// popover rather than .help, which doesn't show in the floating panel.
    @State private var showsClient = false
    @State private var hoverWait: Task<Void, Never>?

    private var isBusy: Bool { tracker.busyKey == task.key }
    /// Shows the state you just asked for while Harvest confirms it, instead
    /// of a spinner.
    private var isRunning: Bool {
        let running = tracker.running?.key == task.key
        if isBusy { return !running }
        // Another tile is starting: this one stops with it, so let it go
        // right away rather than when Harvest confirms.
        if running, let busy = tracker.busyKey, busy != task.key { return false }
        return running
    }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        // Not a Button: on macOS a button keeps the mouse press to itself, so
        // the tile could never be dragged. A tap starts or pauses instead.
        styledContent
            .modifier(TileChrome(isRunning: isRunning, isSelected: isSelected, isHovered: isHovered))
            .unavailableTask(task.key)
            .onTapGesture {
                showsClient = false
                Task { await tracker.toggle(task) }
            }
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
            guard let dropBefore, let key = items.first.flatMap(TaskKey.init), key != task.key else { return false }
            var taken = false
            withAnimation(.snappy(duration: 0.2)) { taken = dropBefore(key) }
            return taken
        } isTargeted: { targeted in
            withAnimation(.snappy(duration: 0.15)) { isDropTarget = dropBefore != nil && targeted }
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
        .onHover { hovering in
            isHovered = hovering
            hoverWait?.cancel()
            guard hovering, task.client?.name.isEmpty == false else { return showsClient = false }
            hoverWait = Task {
                try? await Task.sleep(for: .milliseconds(700))
                if !Task.isCancelled { showsClient = true }
            }
        }
        .background {
            Color.clear.popover(isPresented: $showsClient, arrowEdge: .top) {
                Text(task.client?.name ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: 260)
                    .fixedSize()
            }
        }
        #endif
        .contextMenu {
            Button(isRunning ? "Pause Timer" : "Start Timer", systemImage: isRunning ? "pause.fill" : "play.fill") {
                Task { await tracker.toggle(task) }
            }
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                tracker.favorites.toggle(task.key)
            }
            if TaskGroups.customGroupsEnabled { groupMenu }
            if let onRemove {
                Button("Remove from Suggested", systemImage: "xmark", action: onRemove)
            }
        }
        #if !os(macOS)
        .help(task.helpText)
        #endif
        .accessibilityLabel("\(task.project.name), \(task.task.name), \(task.client?.name ?? "")")
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts a timer")
    }

    /// Add to Group › each group (checked when it's in it) and New Group.
    @ViewBuilder private var groupMenu: some View {
        let groups = TaskGroups.shared
        if let groupID, let group = groups.groups.first(where: { $0.id == groupID }) {
            Button("Remove from \(group.name)", systemImage: "folder.badge.minus") {
                withAnimation(.snappy(duration: 0.2)) { groups.toggle(task.key, in: groupID) }
            }
        }
        Menu("Add to Group", systemImage: "folder.badge.plus") {
            ForEach(groups.groups) { group in
                Toggle(group.name, isOn: Binding(
                    get: { groups.contains(task.key, in: group.id) },
                    set: { _ in withAnimation(.snappy(duration: 0.2)) { groups.toggle(task.key, in: group.id) } }
                ))
            }
            if !groups.groups.isEmpty { Divider() }
            Button("New Group…") { withAnimation(.snappy(duration: 0.2)) { _ = groups.create(with: task.key) } }
        }
    }

    @ViewBuilder private var styledContent: some View {
        switch style {
        case .classic: content
        case .launcher: LauncherTileContent(task: task, isRunning: isRunning)
        case .rows: IconRowContent(task: task, isRunning: isRunning)
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            let (code, name) = task.projectNameParts
            let entryLike = TileText(rawValue: tileTextRaw) != .codeOnTop
            // Like a tracked entry: client, "[code] name", task. Or the code
            // on top: code, name, task. Three lines either way, so every
            // tile is the same height.
            VStack(alignment: .leading, spacing: 1) {
                Text(entryLike ? task.client?.name ?? " " : code ?? " ")
                    .font(entryLike ? .system(size: codeFont) : .system(size: codeFont, weight: .medium).monospaced())
                    .opacity(isRunning ? 0.82 : 0.55)
                // Hover slides a name that doesn't fit across to show the rest.
                MarqueeText(text: entryLike ? code.map { "[\($0)] \(name)" } ?? name : name, isActive: isHovered)
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
                }
                .buttonStyle(TileIconButtonStyle())
                .help("Remove from Suggested")
                .accessibilityLabel("Remove \(task.task.name) from Suggested")
            }
            if showsStar && (isHovered || isFavorite) { favoriteButton }
            actionIndicator
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .padding(.vertical, 5)
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
        .font(.system(size: 8, weight: .bold))
        .frame(width: indicatorSize, height: indicatorSize)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var favoriteButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.toggle(task.key) }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(TileIconButtonStyle(tint: starStyle,
                                         hoverTint: isFavorite ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary),
                                         onOrange: isRunning))
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
    private let subtitleFont: CGFloat = 11
    private let indicatorSize: CGFloat = 22
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

/// The small × and ☆ on a tile: faint at rest; on hover a soft circle
/// shows behind it and it darkens, so it reads as its own button.
private struct TileIconButtonStyle: ButtonStyle {
    var tint: AnyShapeStyle = AnyShapeStyle(.tertiary)
    var hoverTint: AnyShapeStyle = AnyShapeStyle(.secondary)
    var onOrange = false

    func makeBody(configuration: Configuration) -> some View {
        Hovering { isHovered in
            configuration.label
                .foregroundStyle(isHovered && !onOrange ? hoverTint : tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(onOrange ? Color.white.opacity(isHovered ? 0.25 : 0)
                                          : Color.primary.opacity(isHovered ? 0.09 : 0)))
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.12), value: isHovered)
        }
    }
}

/// Hands its content whether the pointer is over it.
private struct Hovering<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        content(isHovered)
        #if os(macOS)
            .onHover { isHovered = $0 }
        #endif
    }
}
