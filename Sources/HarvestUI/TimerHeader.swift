import HarvestKit
import SwiftUI

/// The running timer (with notes and Stop), or today's total when idle.
struct TimerHeader: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        Group {
            if let entry = tracker.running {
                RunningCard(entry: entry, task: tracker.task(for: entry))
                    .id(entry.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                IdleCard()
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: tracker.running?.id)
    }
}

private struct RunningCard: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .symbolEffect(.pulse, options: .repeating)
                        Text("TRACKING")
                            .font(.caption2.weight(.bold))
                            .tracking(0.6)
                    }
                    .foregroundStyle(.harvestOrange)
                    Text(task.task.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(task.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(TimeFormat.clock(entry.elapsed(at: context.date)))
                            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("Today \(TimeFormat.hoursMinutes(tracker.todaySeconds(at: context.date)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    Task { await tracker.stop() }
                } label: {
                    if tracker.busyKey == entry.key {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "stop.fill")
                    }
                }
                .buttonStyle(OrangeCircleButtonStyle(size: Metrics.actionSize + 12))
                .help("Stop timer (⌘.)")
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stop timer")
            }

            TextField("What are you working on?", text: $notes, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...3)
                .focused($notesFocused)
                .onSubmit(save)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.background.opacity(0.7)))
                .onChange(of: notesFocused) { _, focused in if !focused { save() } }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.harvestOrange.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.harvestOrange.opacity(0.25)))
        .onAppear { notes = entry.notes ?? "" }
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await tracker.updateNotes(trimmed, for: entry) }
    }
}

private struct IdleCard: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("No timer running")
                    .font(.headline)
                Text("Pick a task to start tracking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("TODAY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(TimeFormat.hoursMinutes(tracker.todaySeconds()))
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.quaternary.opacity(0.6)))
    }
}
