import HarvestKit
import SwiftUI

/// A slim bar at the top: the running timer with notes and Pause, today's last
/// entry with Resume, or today's total.
struct TimerHeader: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        Group {
            if let entry = tracker.running {
                RunningBar(entry: entry, task: tracker.task(for: entry))
                    .id(entry.id)
            } else if let entry = tracker.pausedEntry {
                PausedBar(entry: entry, task: tracker.task(for: entry))
            } else {
                IdleBar()
            }
        }
        .animation(.snappy(duration: 0.2), value: tracker.running?.id)
    }
}

private struct Bar<Content: View>: View {
    var filled = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(filled ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(Color.tileBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(filled ? Color.clear : Color.primary.opacity(0.07))
            )
    }
}

private struct RunningBar: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        Bar(filled: true) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .symbolEffect(.pulse, options: .repeating)

            VStack(alignment: .leading, spacing: 1) {
                (Text(task.project.name).fontWeight(.semibold) + Text("  \(task.task.name)").foregroundStyle(.white.opacity(0.8)))
                    .font(.system(size: 13))
                    .lineLimit(1)
                TextField("Notes", text: $notes, prompt: Text("Add notes…").foregroundStyle(.white.opacity(0.65)))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .focusEffectDisabled()
                    .focused($notesFocused)
                    .onSubmit(save)
                    .onChange(of: notesFocused) { _, focused in if !focused { save() } }
            }

            Spacer(minLength: 4)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimeFormat.clock(entry.elapsed(at: context.date)))
                    .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            }

            Button {
                Task { await tracker.pause() }
            } label: {
                if tracker.busyKey == entry.key {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "pause.fill")
                }
            }
            .buttonStyle(CircleButtonStyle(size: 34, fill: .white, glyph: .harvestOrange))
            .keyboardShortcut(".", modifiers: .command)
            .help("Pause timer (⌘.)")
            .accessibilityLabel("Pause timer")
        }
        .foregroundStyle(.white)
        .tint(.white)
        .onAppear { notes = entry.notes ?? "" }
    }

    private func save() {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await tracker.updateNotes(trimmed, for: entry) }
    }
}

private struct PausedBar: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask

    var body: some View {
        Bar {
            Image(systemName: "pause.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.harvestOrange)
            VStack(alignment: .leading, spacing: 1) {
                (Text(task.project.name).fontWeight(.semibold) + Text("  \(task.task.name)").foregroundStyle(.secondary))
                    .font(.system(size: 13))
                    .lineLimit(1)
                Text("Paused at \(TimeFormat.hoursMinutes(entry.elapsed())) · Today \(TimeFormat.hoursMinutes(tracker.todaySeconds()))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                Task { await tracker.resume() }
            } label: {
                if tracker.busyKey == entry.key {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "play.fill").offset(x: 1)
                }
            }
            .buttonStyle(CircleButtonStyle(size: 34))
            .help("Resume timer")
            .accessibilityLabel("Resume \(task.task.name)")
        }
    }
}

private struct IdleBar: View {
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        Bar {
            VStack(alignment: .leading, spacing: 1) {
                Text("No timer running").font(.system(size: 13, weight: .semibold))
                Text("Pick a task to start tracking").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Today \(TimeFormat.hoursMinutes(tracker.todaySeconds()))")
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .padding(.trailing, 4)
        }
    }
}
