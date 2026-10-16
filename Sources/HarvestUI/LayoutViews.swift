import HarvestKit
import SwiftUI

/// The three ways the main window can be laid out, picked in the bottom bar.
enum WindowLayout: String, CaseIterable, Identifiable {
    /// Today's layout with a large "What are you working on?" box on top.
    case classic
    /// Large favorite tiles with today's time on each.
    case tiles
    /// One numbered list of things to start.
    case list

    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .tiles: return "Tiles"
        case .list: return "List"
        }
    }
    var systemImage: String {
        switch self {
        case .classic: return "rectangle.grid.1x2"
        case .tiles: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}

extension TimeTracker {
    /// Time on this task today, counting a running timer.
    func secondsToday(for task: TrackableTask, at now: Date = .now) -> TimeInterval {
        entries(on: LocalDate(now)).filter { $0.key == task.key }.reduce(0) { $0 + $1.elapsed(at: now) }
    }
}

// MARK: Big tiles

/// Favorites (topped up with recent tasks) as large square buttons, each with
/// today's time. The running one is solid orange.
struct BigTilesView: View {
    @Environment(TimeTracker.self) private var tracker
    let openSearch: () -> Void

    private var tasks: [TrackableTask] {
        var result = tracker.favoriteTasks
        if result.count < 4 {
            let seen = Set(result.map(\.key))
            result += tracker.recentTasks.filter { !seen.contains($0.key) }.prefix(4 - result.count)
        }
        return result
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(tasks) { task in
                    BigTile(task: task, seconds: tracker.secondsToday(for: task, at: context.date))
                }
                Button(action: openSearch) {
                    Label("Add a favorite", systemImage: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Search for a task, then star it")
            }
        }
    }
}

private struct BigTile: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let seconds: TimeInterval
    @State private var isHovered = false
    @State private var isDropTarget = false

    private var isRunning: Bool {
        let running = tracker.running?.key == task.key
        return tracker.busyKey == task.key ? !running : running
    }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        let (code, name) = task.projectNameParts
        VStack(alignment: .leading, spacing: 0) {
            if let code {
                Text(code).font(.system(size: 10, weight: .medium).monospaced()).opacity(0.55)
            }
            Text(name)
                .font(.system(size: 16, weight: .medium))
                .lineLimit(2)
            Text(task.task.name)
                .font(.system(size: 12))
                .opacity(0.7)
                .lineLimit(1)
                .padding(.top, 2)
            Spacer(minLength: 8)
            HStack(alignment: .bottom) {
                Text(TimeFormat.hoursMinutes(seconds))
                    .font(.system(size: 24, weight: .regular).monospacedDigit())
                    .opacity(seconds > 0 || isRunning ? 1 : 0.35)
                Spacer()
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isRunning ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(isHovered ? .white : .harvestOrange))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isRunning ? AnyShapeStyle(.white)
                                              : AnyShapeStyle(Color.harvestOrange.opacity(isHovered ? 1 : 0.13))))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .foregroundStyle(isRunning ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isRunning ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(Color.tileBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isRunning ? Color.clear : Color.primary.opacity(isHovered ? 0.16 : 0.07))
        )
        .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 6 : 2, y: isHovered ? 2 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { Task { await tracker.toggle(task) } }
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .draggable(task.key.description)
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first.flatMap(TaskKey.init) else { return false }
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.place(key, before: isFavorite ? task.key : nil) }
            return true
        } isTargeted: { targeted in withAnimation(.snappy(duration: 0.15)) { isDropTarget = targeted } }
        .offset(x: isDropTarget ? 6 : 0)
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule().fill(Color.harvestOrange).frame(width: 3).padding(.vertical, 4).offset(x: -6.5)
            }
        }
        .contextMenu {
            Button(isRunning ? "Pause Timer" : "Start Timer") { Task { await tracker.toggle(task) } }
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { tracker.favorites.toggle(task.key) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await tracker.toggle(task) } }
    }
}

// MARK: One list

/// Favorites, then recent and suggested, as one numbered list of rows that
/// all look and work the same. ⌘1–⌘9 start the first nine.
struct StartListView: View {
    @Environment(TimeTracker.self) private var tracker

    private var tasks: [TrackableTask] {
        var seen = Set<TaskKey>()
        return (tracker.favoriteTasks + tracker.recentTasks + tracker.suggestedTasks).filter { seen.insert($0.key).inserted }
    }

    var body: some View {
        let tasks = tasks
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Start").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("⌘1–⌘9 · drag to reorder").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    StartRow(task: task, number: index + 1)
                    if index < tasks.count - 1 { Divider().padding(.leading, 36) }
                }
            }
            .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.tileBackground))
            .overlay(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous))
        }
        .background {
            // ⌘1–⌘9 start the first nine rows.
            ForEach(Array(tasks.prefix(9).enumerated()), id: \.element.id) { index, task in
                Button("") { Task { await tracker.toggle(task) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct StartRow: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let number: Int
    @State private var isHovered = false
    @State private var isDropTarget = false

    private var isRunning: Bool {
        let running = tracker.running?.key == task.key
        return tracker.busyKey == task.key ? !running : running
    }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        let (code, name) = task.projectNameParts
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.harvestOrange)
                    }
                }
                Text([task.task.name, code].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isRunning || isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.harvestOrange.opacity(isRunning || isHovered ? 1 : 0.13)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isRunning ? Color.harvestOrange.opacity(0.10) : isHovered ? Color.primary.opacity(0.04) : .clear)
        .overlay(alignment: .top) {
            if isDropTarget { Rectangle().fill(Color.harvestOrange).frame(height: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await tracker.toggle(task) } }
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .draggable(task.key.description)
        .dropDestination(for: String.self) { items, _ in
            guard let key = items.first.flatMap(TaskKey.init) else { return false }
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.place(key, before: isFavorite ? task.key : nil) }
            return true
        } isTargeted: { isDropTarget = $0 }
        .contextMenu {
            Button(isRunning ? "Pause Timer" : "Start Timer") { Task { await tracker.toggle(task) } }
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { tracker.favorites.toggle(task.key) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
