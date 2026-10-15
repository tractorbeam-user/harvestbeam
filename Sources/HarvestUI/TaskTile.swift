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
            Menu("Move to Folder") {
                ForEach(tracker.favorites.folders, id: \.self) { folder in
                    Button(folder) { tracker.favorites.file(task.key, in: folder) }
                        .disabled(tracker.favorites.folderOf[task.key] == folder)
                }
                if !tracker.favorites.folders.isEmpty { Divider() }
                Button("New Folder…") {
                    tracker.favorites.file(task.key, in: tracker.favorites.createFolder())
                }
                if tracker.favorites.folderOf[task.key] != nil {
                    Button("Remove from Folder") { tracker.favorites.file(task.key, in: nil) }
                }
            }
        }
        .draggable(task.key.description)
        .accessibilityHint(isRunning ? "Pauses the timer" : "Starts a timer")
    }

    private var content: some View {
        // Client, then project, then task — the same order as the day list,
        // since many projects share task names like "Product Design".
        VStack(alignment: .leading, spacing: 0) {
            Text(task.client?.name ?? " ")
                .font(.caption)
                .lineLimit(1)
                .opacity(0.6)
                .padding(.trailing, 30) // room for the star

            Text(task.project.name)
                .font(.system(.body, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.top, 4)

            Spacer(minLength: 6)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.task.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .opacity(0.8)
                    if let code = task.projectCode {
                        Text(code)
                            .font(.caption2.monospaced())
                            .lineLimit(1)
                            .opacity(0.5)
                    }
                }
                Spacer(minLength: 6)
                actionIndicator
            }
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
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(1)
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
