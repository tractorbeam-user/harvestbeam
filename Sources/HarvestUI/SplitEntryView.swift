import HarvestKit
import SwiftUI

/// Right-click › Split Entry…: send some of this entry's time to another task
/// on the same day. A running timer keeps running with what's left.
struct SplitEntryView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    let entry: TimeEntry
    let task: TrackableTask

    @State private var amount = ""
    @State private var query = ""
    @State private var destination: TrackableTask?
    @State private var isSaving = false
    @FocusState private var searchFocused: Bool

    private var total: TimeInterval { entry.elapsed() }
    private var moving: TimeInterval? { TimeFormat.parseHours(amount).map { $0 * 3600 } }
    private var results: [TrackableTask] {
        let found = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? tracker.favoriteTasks + tracker.recentTasks
            : tracker.search(query)
        var seen = Set<TaskKey>()
        return found.filter {
            !$0.isProjectRow && $0.key != task.key && tracker.isAvailable($0.key) && seen.insert($0.key).inserted
        }.prefix(6).map { $0 }
    }
    private var problem: String? {
        guard let moving else { return amount.isEmpty ? nil : "Try 20m, 1:15 or 0.5" }
        if moving < 60 { return "Move at least a minute" }
        if moving > total - (entry.isRunning ? 60 : 0) { return "Only \(TimeFormat.hoursMinutes(total)) to move" }
        return nil
    }
    private var canMove: Bool { moving != nil && problem == nil && destination != nil && !isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Split Entry").font(.system(size: 13, weight: .semibold))
                Text("\(task.project.name) · \(task.task.name) · \(TimeFormat.hoursMinutes(total))")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }

            // How much
            VStack(alignment: .leading, spacing: 6) {
                Text("Move").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    TextField("0:20", text: $amount)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .font(.system(size: 13).monospacedDigit())
                    ForEach(quickAmounts, id: \.label) { quick in
                        Button(quick.label) { amount = TimeFormat.hoursMinutes(quick.seconds) }
                            .buttonStyle(ChipButtonStyle(isOn: moving.map { abs($0 - quick.seconds) < 30 } ?? false))
                    }
                }
                if let problem {
                    Text(problem).font(.system(size: 11)).foregroundStyle(.red)
                }
            }

            // Where to
            VStack(alignment: .leading, spacing: 6) {
                Text("To").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                TextField("Search tasks", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                VStack(spacing: 2) {
                    ForEach(results) { option in
                        Button { destination = option } label: {
                            HStack(spacing: 8) {
                                Image(systemName: destination?.key == option.key ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(destination?.key == option.key ? AnyShapeStyle(Color.harvestOrange) : AnyShapeStyle(.tertiary))
                                    .font(.system(size: 12))
                                Text(option.project.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(option.task.name).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(destination?.key == option.key ? Color.orangeSoft : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if results.isEmpty {
                        Text("No tasks match").font(.system(size: 12)).foregroundStyle(.secondary).padding(6)
                    }
                }
            }

            Divider()

            HStack {
                if let moving, problem == nil, let destination {
                    Text("Leaves \(TimeFormat.hoursMinutes(total - moving)) here, logs \(TimeFormat.hoursMinutes(moving)) on \(destination.task.name)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isSaving ? "Moving…" : "Move Time") { Task { await move() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canMove)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            // Half is a common starting point; you'll usually change it.
            amount = TimeFormat.hoursMinutes((total / 2 / 60).rounded(.down) * 60)
        }
    }

    private var quickAmounts: [(label: String, seconds: TimeInterval)] {
        [("15m", 900), ("30m", 1800), ("1h", 3600), ("Half", (total / 2 / 60).rounded(.down) * 60)]
            .filter { $0.1 >= 60 && $0.1 <= total - 60 }
    }

    private func move() async {
        guard let moving, let destination else { return }
        isSaving = true
        defer { isSaving = false }
        if await tracker.moveTime(moving, from: entry, to: destination, notes: entry.notes ?? "") { dismiss() }
    }
}

private struct ChipButtonStyle: ButtonStyle {
    let isOn: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(Capsule().fill(isOn ? Color.harvestOrange : Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06)))
    }
}

#if DEBUG
/// The split popover on the running timer, for the debug snapshots.
@MainActor public func debugSplitEntry(_ tracker: TimeTracker) -> some View {
    Group {
        if let entry = tracker.running ?? tracker.entries(on: LocalDate()).first,
           let task = tracker.tasks.first(where: { $0.key == entry.key }) {
            SplitEntryView(entry: entry, task: task)
        }
    }
}
#endif
