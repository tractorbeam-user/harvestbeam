import HarvestKit
import SwiftUI

/// Harvest-style day view: a week strip with each day's total, then that
/// day's entries with play/pause.
struct DayView: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate

    var body: some View {
        VStack(spacing: 12) {
            WeekStrip(selectedDay: $selectedDay)
            ShortDayNudge(selectedDay: $selectedDay)
            DayEntriesList(day: selectedDay)
        }
    }
}

extension LocalDate {
    /// "Today, Oct 15", "Yesterday, Oct 14", or "Monday, Oct 12".
    func dayTitle(today: LocalDate) -> String {
        let date = date()
        let dayMonth = date.formatted(.dateTime.day().month(.abbreviated))
        switch days(until: today) {
        case 0: return "Today, \(dayMonth)"
        case 1: return "Yesterday, \(dayMonth)"
        case -1: return "Tomorrow, \(dayMonth)"
        default: return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }
}

extension TimeTracker {
    /// Total tracked in the calendar month that contains `day`.
    func monthSeconds(containing day: LocalDate, at now: Date = .now) -> TimeInterval {
        entries.reduce(0) { total, entry in
            entry.spentDate.year == day.year && entry.spentDate.month == day.month ? total + entry.elapsed(at: now) : total
        }
    }

    /// Total tracked in the week that contains `day`.
    func weekSeconds(containing day: LocalDate, at now: Date = .now) -> TimeInterval {
        let start = day.startOfWeek(firstWeekday: firstWeekday)
        return (0..<7).reduce(0) { $0 + seconds(on: start.adding(days: $1), at: now) }
    }
}

private struct WeekStrip: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.windowActions) private var windowActions
    @Binding var selectedDay: LocalDate
    @AppStorage(ShortDays.enabledKey) private var nudgesShortDays = true

    private var weekStart: LocalDate { selectedDay.startOfWeek(firstWeekday: tracker.firstWeekday) }

    var body: some View {
        let today = LocalDate()
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 12) {
                // The Mac window shows the day, week total and Today in its title bar instead.
                if windowActions == nil {
                    HStack(alignment: .firstTextBaseline) {
                        Text(selectedDay.dayTitle(today: today))
                            .font(.headline)
                        Spacer()
                        Text("Week \(TimeFormat.hoursMinutes(tracker.weekSeconds(containing: selectedDay, at: context.date)))")
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
                }

                HStack(spacing: 0) {
                    arrow("chevron.left", help: "Previous day (⌘[)") { select(selectedDay.adding(days: -1)) }
                    ForEach(0..<7, id: \.self) { offset in
                        dayButton(weekStart.adding(days: offset), today: today, now: context.date)
                    }
                    arrow("chevron.right", help: "Next day (⌘])") { select(selectedDay.adding(days: 1)) }
                }
            }
        }
        #if os(macOS)
        // Straight on the white window, no card.
        .padding(.top, 2)
        #else
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.tileBackground))
        .overlay(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).strokeBorder(Color.hairline))
        #endif
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

    private func arrow(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 38)
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
        let isShort = nudgesShortDays && !isSelected && tracker.shortDays(today: today).contains(day)
        return Button { select(day) } label: {
            // The selected day is a pale orange pill holding its letter and
            // total; today is orange wherever you are in the week.
            VStack(spacing: 1) {
                Text(letter)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected || isToday ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.secondary))
                Text(TimeFormat.hoursMinutes(seconds))
                    .font(.caption.weight(isSelected ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected || isToday ? AnyShapeStyle(.harvestOrange) : isShort ? AnyShapeStyle(Color.shortDay) : seconds > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            }
            // A small amber dot on days earlier this week that came up short.
            .overlay(alignment: .top) {
                if isShort {
                    Circle().fill(Color.shortDayDot).frame(width: 5, height: 5).offset(x: 9, y: -1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? Color.orangeSoft : .clear))
            .padding(.horizontal, 1)
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
    @State private var isAdding = false

    var body: some View {
        let entries = tracker.entries(on: day)
        Group {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Text(day == LocalDate() ? "Nothing tracked yet today" : "No time tracked")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button { isAdding = true } label: {
                        Label("New Entry", systemImage: "plus")
                    }
                    .buttonStyle(SoftPillButtonStyle())
                        .popover(isPresented: $isAdding, arrowEdge: .bottom) { NewEntryEditor(day: day) }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry, task: tracker.task(for: entry))
                        if index < entries.count - 1 {
                            Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, 14)
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(Color.tileBackground))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).strokeBorder(Color.hairline))
    }
}

private struct EntryRow: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let task: TrackableTask
    @Environment(\.openURL) private var openURL
    @State private var isHovered = false
    @State private var isEditing = false
    @State private var isShowingLock = false
    private var isFavorite: Bool { tracker.favorites.contains(entry.key) }
    /// Approved, invoiced or locked: Harvest won't let it change.
    private var lock: EntryLock? { entry.lock }

    var body: some View {
        // Double-click (or double-tap) edits; only the round button starts or
        // pauses, so a double-click never toggles the timer by accident.
        HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if let client = task.client?.name {
                        Text(client)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    MarqueeText(text: task.project.name, isActive: isHovered)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(lock == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Text(task.task.name)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
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
                            .foregroundStyle(lock == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                }
                .font(.system(size: 20, weight: .medium, design: .rounded).monospacedDigit())

                if let lock {
                    // A lock where play would be; it says why.
                    Button { isShowingLock = true } label: { lockIndicator }
                        .buttonStyle(.plain)
                        .help("\(lock.title) · can't be edited")
                        .accessibilityLabel("\(lock.title), can't be edited")
                        .popover(isPresented: $isShowingLock, arrowEdge: .bottom) { LockExplanation(lock: lock, day: entry.spentDate) }
                } else {
                    Button {
                        Task { await tracker.toggle(entry) }
                    } label: {
                        actionIndicator
                    }
                    .buttonStyle(.plain)
                    .help(entry.isRunning ? "Pause timer" : "Start timer")
                    .accessibilityLabel(entry.isRunning ? "Pause timer" : "Start timer")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 64)
            .background(background)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { if lock == nil { isEditing = true } else { isShowingLock = true } }
            .help(lock == nil ? "Double-click to edit" : "\(lock!.title) · double-click to see why it's locked")
            // Drag an entry into Favorites, like a tile.
            .draggable(entry.key.description)
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .contextMenu {
            // A new timer today for the same project and task, leaving this entry alone.
            Button(entry.spentDate == LocalDate() ? "Start a Fresh Timer" : "Start Again Today") {
                Task { await tracker.addEntry(task: task, on: LocalDate(), notes: "", hours: nil) }
            }
            Divider()
            if let lock {
                Button("Why Is This \(lock.title)?") { isShowingLock = true }
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { tracker.favorites.toggle(entry.key) }
            } else {
                Button("Edit Entry") { isEditing = true }
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { tracker.favorites.toggle(entry.key) }
                Button(entry.isRunning ? "Stop Timer" : "Start Timer") {
                    Task { await tracker.toggle(entry) }
                }
                Button("Delete Entry", role: .destructive) { Task { await tracker.deleteEntry(entry) } }
            }
            Divider()
            Button("View in Harvest") {
                if let url = tracker.harvestURL(for: entry.spentDate) { openURL(url) }
            }
        }
        .popover(isPresented: $isEditing, arrowEdge: .bottom) { NewEntryEditor(day: entry.spentDate, entry: entry) }
        .accessibilityAction(named: "Edit Entry") { isEditing = true }
    }

    private var background: Color {
        if entry.isRunning { return .orangeSoft }
        if lock != nil { return Color.primary.opacity(isHovered ? 0.04 : 0.02) }
        return isHovered ? Color.primary.opacity(0.03) : .clear
    }

    private var lockIndicator: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.primary.opacity(isHovered ? 0.09 : 0.05)))
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    @ViewBuilder private var actionIndicator: some View {
        Group {
            // While Harvest confirms, show the state you asked for, not a spinner.
            if tracker.busyKey == entry.key ? !entry.isRunning : entry.isRunning {
                Image(systemName: "pause.fill")
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.harvestOrange))
            } else {
                Image(systemName: "play.fill")
                    .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isHovered ? Color.harvestOrange : Color.orangeSoft))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .frame(width: 32, height: 32)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

/// Soft orange pill, matching the play buttons on tiles: tinted at rest,
/// solid on hover.
struct SoftPillButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange))
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(Capsule().fill(isHovered ? Color.harvestOrange : Color.orangeSoft))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
    }
}

#if DEBUG
/// For offscreen snapshots: the short-day nudge as of `today`, over a day
/// with locked entries.
@MainActor public func debugShortDayAndLocks(today: LocalDate, lockedDay: LocalDate) -> some View {
    VStack(spacing: 12) {
        ShortDayNudge(selectedDay: .constant(today), today: today)
        DayEntriesList(day: lockedDay)
        LockExplanation(lock: TimeEntry(
            id: 0, spentDate: lockedDay, project: NamedRef(id: 0, name: ""), task: NamedRef(id: 0, name: ""), client: nil,
            hours: 0, isBilled: true, invoice: .init(id: 1042, number: "1042")).lock!, day: lockedDay)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tileBackground))
    }
    .padding(14)
}
#endif

/// Why an entry can't be edited, and where to go about it.
struct LockExplanation: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.openURL) private var openURL
    let lock: EntryLock
    let day: LocalDate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.harvestOrange)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(lock.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(lock.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = tracker.harvestURL(for: day) {
                    Button { openURL(url) } label: {
                        Label("View in Harvest", systemImage: "arrow.up.forward")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.harvestOrange)
                    .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .dimsWindow()
        .presentationBackground(Color.tileBackground)
    }

    private var icon: String {
        switch lock.kind {
        case .invoiced: "doc.text"
        case .approved: "checkmark.seal"
        case .locked: "lock"
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.font(.system(size: 10, weight: .bold))
        }
    }
}

extension Color {
    /// Amber for a short day's total and the nudge's text.
    static var shortDay: Color {
        #if os(macOS)
        .adaptive(light: 0x854F0B, dark: 0xFAC775)
        #else
        Color(red: 0x85 / 255, green: 0x4F / 255, blue: 0x0B / 255)
        #endif
    }

    static var shortDayDot: Color { Color(red: 0xEF / 255, green: 0x9F / 255, blue: 0x27 / 255) }

    /// The nudge's pale amber fill.
    static var shortDayFill: Color {
        #if os(macOS)
        .adaptive(light: 0xFAEEDA, dark: 0xEF9F27, alpha: 1, darkAlpha: 0.16)
        #else
        Color(red: 0xFA / 255, green: 0xEE / 255, blue: 0xDA / 255)
        #endif
    }
}

/// "Thursday only has 3:10 · Open Thursday", for the most recent day earlier
/// this week that's well short of a usual day. Dismissing hides it for that
/// day; Preferences can turn it off altogether.
private struct ShortDayNudge: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var selectedDay: LocalDate
    var today = LocalDate()
    @AppStorage(ShortDays.enabledKey) private var isEnabled = true
    @AppStorage(ShortDays.dismissedKey) private var dismissedRaw = ""

    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        if isEnabled, let day = tracker.shortDays(today: today).last(where: { $0 != selectedDay && !dismissed.contains($0.description) }) {
            let seconds = tracker.seconds(on: day)
            let weekday = day.date().formatted(.dateTime.weekday(.wide))
            HStack(spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.shortDay)
                VStack(alignment: .leading, spacing: 1) {
                    Text(seconds < 60 ? "Nothing tracked \(weekday)" : "\(weekday) only has \(TimeFormat.hoursMinutes(seconds))")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("\(TimeFormat.hoursMinutes(tracker.usualDaySeconds - seconds)) short of a usual day")
                        .font(.system(size: 11.5))
                        .opacity(0.85)
                }
                .foregroundStyle(Color.shortDay)
                .lineLimit(1)
                Spacer(minLength: 4)
                Button("Open \(weekday)") {
                    withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
                }
                .buttonStyle(NudgeButtonStyle())
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        dismissedRaw = (dismissed.union([day.description])).sorted().suffix(20).joined(separator: ",")
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.shortDay.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss for \(weekday)")
                .accessibilityLabel("Dismiss for \(weekday)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.shortDayFill))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

private struct NudgeButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.shortDay)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(Color.tileBackground.opacity(isHovered ? 1 : 0.85)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            #if os(macOS)
            .onHover { isHovered = $0 }
            #endif
    }
}
