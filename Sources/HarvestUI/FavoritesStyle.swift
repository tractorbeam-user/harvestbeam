import HarvestKit
import SwiftUI

/// How a tile's three lines read: like a tracked entry (client, "[code]
/// name", task), or with the code on top (code, name, task).
public enum TileText: String, CaseIterable, Identifiable {
    case entry, codeOnTop

    public static let key = "tileText"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .entry: return "Client, Code and Name, Task"
        case .codeOnTop: return "Code, Name, Task"
        }
    }
}

/// How Favorites' tiles look: the regular tiles, a grid of big launcher
/// tiles, or rows led by a big icon.
public enum FavoritesStyle: String, CaseIterable, Identifiable {
    case classic, launcher, rows

    public static let key = "favoritesStyle"
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .classic: return "Tiles"
        case .launcher: return "Launcher Grid"
        case .rows: return "Rows"
        }
    }

    /// The narrowest a tile gets before the grid drops a column.
    var minWidth: CGFloat {
        switch self {
        case .classic, .rows: return Metrics.tileMinWidth
        case .launcher: return 112
        }
    }
}

/// A launcher tile: big icon on top, then the name and task. The running one
/// is solid orange with today's time in the corner.
struct LauncherTileContent: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let isRunning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if task.projectNameParts.code != nil || isRunning {
            HStack(alignment: .top) {
                Text(task.projectNameParts.code ?? "")
                    .font(.system(size: 10.5, weight: .medium).monospaced())
                    .opacity(isRunning ? 0.85 : 0.55)
                Spacer(minLength: 4)
                if isRunning {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(TimeFormat.hoursMinutes(tracker.secondsToday(for: task, at: context.date)))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                }
            }
            Spacer(minLength: 4)
            }
            Text(task.projectNameParts.name)
                .font(.system(size: 12.5, weight: .semibold))
            Text(task.task.name)
                .font(.system(size: 11))
                .opacity(isRunning ? 0.82 : 0.6)
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isRunning ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }
}

/// An icon row: a big icon on the left (a pause sign while running), then
/// the name, with the code and task, or today's time, under it. No play
/// button: the whole row starts it.
struct IconRowContent: View {
    @Environment(TimeTracker.self) private var tracker
    let task: TrackableTask
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isRunning {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.22)))
                } else {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.harvestOrange)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orangeSoft))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(task.projectNameParts.name)
                    .font(.system(size: 12.5, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(subtitle(at: context.date))
                        .font(.system(size: 11))
                        .opacity(isRunning ? 0.85 : 0.6)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .foregroundStyle(isRunning ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
    }

    private func subtitle(at now: Date) -> String {
        var parts = [task.projectNameParts.code, task.task.name].compactMap { $0 }
        if isRunning { parts = [task.projectNameParts.code, TimeFormat.hoursMinutes(tracker.secondsToday(for: task, at: now))].compactMap { $0 } }
        return parts.joined(separator: " · ")
    }
}
