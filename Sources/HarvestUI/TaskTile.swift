import HarvestKit
import SwiftUI

/// One project/task as a big, easy-to-hit tile. Click or tap anywhere on it to
/// start its timer (or pause it if it's running); the star pins it.
struct TaskTile: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    var isSelected = false
    @State private var isHovered = false

    private var isRunning: Bool { tracker.running?.key == task.key }
    private var isBusy: Bool { tracker.busyKey == task.key }
    private var isFavorite: Bool { tracker.favorites.contains(task.key) }

    var body: some View {
        Button {
            Task { await tracker.toggle(task) }
        } label: {
            content
        }
        .buttonStyle(TileButtonStyle(isRunning: isRunning, isSelected: isSelected, isHovered: isHovered))
        .overlay(alignment: .topTrailing) { favoriteButton }
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
        }
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts a timer")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectBadge(name: task.project.name, highlighted: isRunning)

            Spacer(minLength: 10)

            Text(task.task.name)
                .font(.system(.body, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(task.project.name)
                .font(.caption)
                .lineLimit(1)
                .opacity(0.75)
                .padding(.top, 2)

            HStack(alignment: .center) {
                Text(task.client?.name ?? " ")
                    .font(.caption)
                    .lineLimit(1)
                    .opacity(0.55)
                Spacer(minLength: 6)
                actionIndicator
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Metrics.tileHeight, alignment: .topLeading)
        .foregroundStyle(isRunning ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }

    @ViewBuilder private var actionIndicator: some View {
        Group {
            if isBusy {
                ProgressView().controlSize(.small).tint(isRunning ? .white : nil)
            } else if isRunning {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.harvestOrange)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white))
            } else {
                Image(systemName: "play.fill")
                    .foregroundStyle(isHovered || isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.harvestOrange.opacity(isHovered || isSelected ? 1 : 0.13)))
            }
        }
        .font(.system(size: 12, weight: .bold))
        .frame(width: 30, height: 30)
    }

    private var favoriteButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { tracker.favorites.toggle(task.key) }
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(starStyle)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(2)
        .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        .accessibilityLabel(isFavorite ? "Remove \(task.task.name) from Favorites" : "Add \(task.task.name) to Favorites")
    }

    private var starStyle: AnyShapeStyle {
        if isRunning { return AnyShapeStyle(.white.opacity(isFavorite ? 1 : 0.6)) }
        if isFavorite { return AnyShapeStyle(.harvestOrange) }
        return AnyShapeStyle(.tertiary)
    }
}

private struct TileButtonStyle: ButtonStyle {
    let isRunning: Bool
    let isSelected: Bool
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous)
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

/// Project initials in a rounded square; inverted on the running (orange) tile.
struct ProjectBadge: View {
    let name: String
    var highlighted = false

    private var initials: String {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: Metrics.badgeSize * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(highlighted ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            .frame(width: Metrics.badgeSize, height: Metrics.badgeSize)
            .background(
                RoundedRectangle(cornerRadius: Metrics.badgeSize * 0.3, style: .continuous)
                    .fill(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(Color.primary.opacity(0.07)))
            )
    }
}
