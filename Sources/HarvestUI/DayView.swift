import HarvestKit
import SwiftUI

/// Harvest-style day view: a week strip with each day's total, then that
/// day's entries with play/pause.
struct DayView: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate

    var body: some View {
        VStack(spacing: 10) {
            WeekStrip(selectedDay: $selectedDay)
            DayEntriesList(day: selectedDay)
        }
    }
}

private struct WeekStrip: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate

    private var weekStart: LocalDate { selectedDay.startOfWeek(firstWeekday: tracker.firstWeekday) }

    var body: some View {
        let today = LocalDate()
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title(today: today))
                        .font(.headline)
                    Spacer()
                    Text("Week \(TimeFormat.hoursMinutes(weekSeconds(at: context.date)))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if selectedDay != today {
                        Button("Today") { select(today) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .keyboardShortcut("t", modifiers: .command)
                            .help("Go to today (⌘T)")
                    }
                }

                HStack(spacing: 0) {
                    arrow("chevron.left", help: "Previous week") { select(selectedDay.adding(days: -7)) }
                    ForEach(0..<7, id: \.self) { offset in
                        dayButton(weekStart.adding(days: offset), today: today, now: context.date)
                    }
                    arrow("chevron.right", help: "Next week") { select(selectedDay.adding(days: 7)) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .background {
            // Previous/next day from the keyboard.
            Group {
                Button("") { select(selectedDay.adding(days: -1)) }.keyboardShortcut("[", modifiers: .command)
                Button("") { select(selectedDay.adding(days: 1)) }.keyboardShortcut("]", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .task(id: weekStart) { await tracker.ensureLoaded(from: weekStart) }
    }

    private func select(_ day: LocalDate) {
        withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
    }

    private func weekSeconds(at now: Date) -> TimeInterval {
        (0..<7).reduce(0) { $0 + tracker.seconds(on: weekStart.adding(days: $1), at: now) }
    }

    private func title(today: LocalDate) -> String {
        let date = selectedDay.date()
        let dayMonth = date.formatted(.dateTime.day().month(.abbreviated))
        switch selectedDay.days(until: today) {
        case 0: return "Today, \(dayMonth)"
        case 1: return "Yesterday, \(dayMonth)"
        case -1: return "Tomorrow, \(dayMonth)"
        default: return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    private func arrow(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func dayButton(_ day: LocalDate, today: LocalDate, now: Date) -> some View {
        let isSelected = day == selectedDay
        let isToday = day == today
        let seconds = tracker.seconds(on: day, at: now)
        let letter = Calendar.current.veryShortStandaloneWeekdaySymbols[day.weekday - 1]
        return Button { select(day) } label: {
            VStack(spacing: 5) {
                Text(letter)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : isToday ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.primary))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isSelected ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.clear)))
                Text(TimeFormat.hoursMinutes(seconds))
                    .font(.caption.weight(isSelected ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected || isToday ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.date().formatted(.dateTime.weekday(.wide).day().month())), \(TimeFormat.hoursMinutes(seconds)) tracked")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct DayEntriesList: View {
    @Environment(TimeTracker.self) private var tracker
    let day: LocalDate

    var body: some View {
        let entries = tracker.entries(on: day)
        Group {
            if entries.isEmpty {
                Text(day == LocalDate() ? "Nothing tracked yet today" : "No time tracked")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry, task: tracker.task(for: entry))
                        if index < entries.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous))
    }
}

private struct EntryRow: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Button {
            Task { await tracker.toggle(entry) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let client = task.client?.name {
                        Text(client)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(task.project.name)
                        .font(.body.weight(.medium))
                    Text(task.task.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 1)
                    }
                }
                .lineLimit(1)
                .multilineTextAlignment(.leading)

                Spacer(minLength: 8)

                Group {
                    if entry.isRunning {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(TimeFormat.hoursMinutes(entry.elapsed(at: context.date)))
                        }
                        .foregroundStyle(.harvestOrange)
                    } else {
                        Text(TimeFormat.hoursMinutes(entry.elapsed()))
                    }
                }
                .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())

                actionIndicator
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 66)
            .background(background)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .contextMenu {
            Button("Edit Entry") { isEditing = true }
            Button(entry.isRunning ? "Stop Timer" : "Start Timer") {
                Task { await tracker.toggle(entry) }
            }
            Button("Delete Entry", role: .destructive) { isConfirmingDelete = true }
            Divider()
            Button("View in Harvest") {
                if let url = tracker.harvestURL(for: entry.spentDate) { openURL(url) }
            }
        }
        .sheet(isPresented: $isEditing) { EntryEditor(entry: entry) }
        .confirmationDialog("Delete this entry?", isPresented: $isConfirmingDelete) {
            Button("Delete Entry", role: .destructive) { Task { await tracker.deleteEntry(entry) } }
        } message: {
            Text("\(task.project.name) · \(task.task.name), \(TimeFormat.hoursMinutes(entry.elapsed())). This also deletes it in Harvest.")
        }
        .accessibilityHint(entry.isRunning ? "Pauses the timer" : "Restarts this entry's timer")
    }

    private var background: Color {
        if entry.isRunning { return Color.harvestOrange.opacity(0.10) }
        return isHovered ? Color.primary.opacity(0.04) : .clear
    }

    @ViewBuilder private var actionIndicator: some View {
        Group {
            if tracker.busyKey == entry.key {
                ProgressView().controlSize(.small)
            } else if entry.isRunning {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.harvestOrange))
            } else {
                Image(systemName: "play.fill")
                    .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.harvestOrange.opacity(isHovered ? 1 : 0.13)))
            }
        }
        .font(.system(size: 12, weight: .bold))
        .frame(width: 32, height: 32)
    }
}
