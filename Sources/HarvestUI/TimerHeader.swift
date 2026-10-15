import HarvestKit
import SwiftUI

/// The big card at the top: the running timer with Pause, today's last entry
/// with Resume, or today's total when there's nothing to resume.
struct TimerHeader: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        Group {
            if let entry = tracker.running {
                RunningCard(entry: entry, task: tracker.task(for: entry))
                    .id(entry.id)
            } else if let entry = tracker.pausedEntry {
                PausedCard(entry: entry, task: tracker.task(for: entry))
            } else {
                IdleCard()
            }
        }
        .transition(.opacity)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .symbolEffect(.pulse, options: .repeating)
                        Text("TRACKING")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                    }
                    .opacity(0.9)
                    Text(task.task.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(task.subtitle)
                        .font(.subheadline)
                        .lineLimit(1)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Button {
                    Task { await tracker.pause() }
                } label: {
                    if tracker.busyKey == entry.key {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "pause.fill")
                    }
                }
                .buttonStyle(CircleButtonStyle(size: 52, fill: .white, glyph: .harvestOrange))
                .keyboardShortcut(".", modifiers: .command)
                .help("Pause timer (⌘.)")
                .accessibilityLabel("Pause timer")
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline) {
                    Text(TimeFormat.clock(entry.elapsed(at: context.date)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    Spacer()
                    Text("Today \(TimeFormat.hoursMinutes(tracker.todaySeconds(at: context.date)))")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .opacity(0.85)
                }
            }

            TextField("Notes", text: $notes, prompt: Text("What are you working on?").foregroundStyle(.white.opacity(0.7)), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(1...3)
                .focused($notesFocused)
                .onSubmit(save)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.18)))
                .onChange(of: notesFocused) { _, focused in if !focused { save() } }
        }
        .foregroundStyle(.white)
        .tint(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(.harvestOrange))
        .onAppear { notes = entry.notes ?? "" }
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await tracker.updateNotes(trimmed, for: entry) }
    }
}

private struct PausedCard: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label("PAUSED", systemImage: "pause.fill")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.harvestOrange)
                Text(task.task.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(task.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(TimeFormat.hoursMinutes(entry.elapsed())) on this · Today \(TimeFormat.hoursMinutes(tracker.todaySeconds()))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            Button {
                Task { await tracker.resume() }
            } label: {
                if tracker.busyKey == entry.key {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "play.fill").offset(x: 2)
                }
            }
            .buttonStyle(CircleButtonStyle(size: 52))
            .help("Resume timer")
            .accessibilityLabel("Resume \(task.task.name)")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color.harvestOrange.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct IdleCard: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("No timer running")
                    .font(.title3.weight(.semibold))
                Text("Pick a task to start tracking")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("TODAY")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text(TimeFormat.hoursMinutes(tracker.todaySeconds()))
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
