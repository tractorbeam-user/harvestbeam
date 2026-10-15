import HarvestKit
import SwiftUI

/// One project/task. Tap anywhere to start (or stop) its timer; the star pins it.
struct TaskRow: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    var isSelected = false
    @State private var isHovered = false

    private var isRunning: Bool { tracker.running?.key == task.key }
    private var isBusy: Bool { tracker.busyKey == task.key }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    /// On the Mac, secondary controls appear on hover or keyboard selection so
    /// the list stays quiet. Touch has no hover, so they're always shown.
    private var showsControls: Bool {
        #if os(macOS)
        isHovered || isSelected
        #else
        true
        #endif
    }

    var body: some View {
        HStack(spacing: 10) {
            ProjectBadge(name: task.project.name, highlighted: isRunning)

            VStack(alignment: .leading, spacing: 1) {
                Text(task.task.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(task.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if showsControls || isFavorite {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tracker.favorites.toggle(task.key) }
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .foregroundStyle(isFavorite ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.tertiary))
                        .frame(width: Metrics.actionSize, height: Metrics.actionSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }

            actionIndicator
                .frame(width: Metrics.actionSize, height: Metrics.actionSize)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: Metrics.rowHeight)
        #if os(macOS)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
        .onHover { isHovered = $0 }
        #endif
        .contentShape(Rectangle())
        .onTapGesture { Task { await tracker.toggle(task) } }
        .contextMenu {
            Button(isRunning ? "Stop Timer" : "Start Timer", systemImage: isRunning ? "stop.fill" : "play.fill") {
                Task { await tracker.toggle(task) }
            }
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.slash" : "star") {
                tracker.favorites.toggle(task.key)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(task.task.name), \(task.subtitle)")
        .accessibilityValue(isRunning ? "Timer running" : isFavorite ? "Favorite" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isRunning ? "Stops the timer" : "Starts a timer")
        .accessibilityAction { Task { await tracker.toggle(task) } }
        .accessibilityAction(named: isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            tracker.favorites.toggle(task.key)
        }
    }

    @ViewBuilder private var actionIndicator: some View {
        if isBusy {
            ProgressView().controlSize(.small)
        } else if isRunning {
            Image(systemName: "stop.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.harvestOrange))
        } else if showsControls {
            Image(systemName: "play.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isHovered || isSelected ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.harvestOrange.opacity(isHovered || isSelected ? 0.15 : 0.08)))
        }
    }

    private var background: Color {
        if isSelected { return Color.harvestOrange.opacity(0.14) }
        if isRunning { return Color.harvestOrange.opacity(0.07) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// Project initials in a rounded square; orange while that project is running.
struct ProjectBadge: View {
    let name: String
    var highlighted = false

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: Metrics.badgeSize * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
            .background(
                RoundedRectangle(cornerRadius: Metrics.badgeSize * 0.28, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.quaternary))
            )
    }
}
