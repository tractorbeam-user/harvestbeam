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
        Button {
            Task { await tracker.toggle(task) }
        } label: {
            content
        }
        .buttonStyle(TileButtonStyle(isRunning: isRunning, isSelected: isSelected, isHovered: isHovered))
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
                        .opacity(0.55)
                }
                Text(name)
                    .font(.system(size: titleFont, weight: .semibold))
                Text(task.task.name)
                    .font(.system(size: subtitleFont))
                    .opacity(0.7)
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
        .padding(.leading, 11)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
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
                    .background(Circle().fill(Color.harvestOrange.opacity(isHovered || isSelected ? 1 : 0.13)).frame(width: indicatorSize, height: indicatorSize))
            }
        }
        .font(.system(size: 9, weight: .bold))
        .frame(width: indicatorSize, height: indicatorSize)
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
    private let titleFont: CGFloat = 12
    private let subtitleFont: CGFloat = 11.5
    private let indicatorSize: CGFloat = 24
    #else
    private let codeFont: CGFloat = 12
    private let titleFont: CGFloat = 15
    private let subtitleFont: CGFloat = 14
    private let indicatorSize: CGFloat = 30
    #endif
}

private struct TileButtonStyle: ButtonStyle {
    let isRunning: Bool
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        configuration.label
            .background(shape.fill(isRunning ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(Color.tileBackground)))
            .overlay(shape.strokeBorder(border, lineWidth: isSelected ? 2 : 1))
            .shadow(color: .black.opacity(isHovered ? 0.10 : 0.04), radius: isHovered ? 6 : 2, y: isHovered ? 2 : 1)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var border: Color {
        if isSelected { return .harvestOrange }
        if isRunning { return .clear }
        return Color.primary.opacity(isHovered ? 0.16 : 0.07)
    }
}
