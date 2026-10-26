#if os(macOS)
import HarvestKit
import SwiftUI

/// A task offered in the ask box's list, with why it's there.
struct AskItem: Identifiable {
    let task: TrackableTask
    /// "today", "usually Mondays", "meeting at 2:00 PM".
    let reason: String?
    /// Suggestions read their reason in orange; recent ones in gray.
    let isSuggestion: Bool
    var id: TaskKey { task.key }
}

/// What drops down from the empty ask box: Recent, then Suggested, like
/// Spotlight. ↑↓ choose, Return starts, typing searches everything instead.
struct AskDropdown: View {
    let recent: [AskItem]
    let suggested: [AskItem]
    /// The highlighted row; nil highlights the first.
    let selection: TaskKey?
    let runningKey: TaskKey?
    let pick: (TrackableTask) -> Void
    let highlight: (TaskKey) -> Void

    private var highlighted: TaskKey? { selection ?? (recent.first ?? suggested.first)?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !recent.isEmpty { section("Recent", recent) }
            if !recent.isEmpty && !suggested.isEmpty { divider }
            if !suggested.isEmpty { section("Suggested", suggested) }
            divider
            Text("↑↓ to choose · type to search everything")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .padding(.bottom, 2)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.tileBackground))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private var divider: some View {
        Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, 2).padding(.vertical, 4)
    }

    private func section(_ title: String, _ items: [AskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 3)
            ForEach(items) { row($0) }
        }
    }

    private func row(_ item: AskItem) -> some View {
        let isOn = highlighted == item.id
        let isRunning = runningKey == item.id
        let parts = item.task.projectNameParts
        return Button { pick(item.task) } label: {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Text(parts.name).fontWeight(.semibold).layoutPriority(2)
                    Text(" · \(item.task.task.name)").layoutPriority(1)
                    if let client = item.task.client?.name {
                        Text(" \(client)").foregroundStyle(isOn ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
                Spacer(minLength: 6)
                Group {
                    if isOn {
                        Text(isRunning ? "↩ pause" : "↩ start")
                    } else if isRunning {
                        Text("running").foregroundStyle(.harvestOrange)
                    } else if let reason = item.reason {
                        Text(reason).foregroundStyle(item.isSuggestion ? AnyShapeStyle(Color.harvestOrange) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.system(size: 11.5))
                .lineLimit(1)
                .fixedSize()
            }
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isOn ? Color.harvestOrange : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlight(item.id) } }
        .help("\(item.task.task.name) · \(item.task.subtitle)")
    }
}
#endif
