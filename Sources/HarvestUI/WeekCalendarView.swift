#if os(macOS)
import AppKit
import HarvestKit
import SwiftUI

/// A week as columns of time, like Harvest's Calendar view: each day's
/// entries stacked from the top by length, with your calendar's meetings
/// that aren't logged yet in blue between them. Click a meeting to log it.
public struct WeekCalendarView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(ActivityRecorder.self) private var recorder: ActivityRecorder?
    let calendar: CalendarStore
    @State private var weekStart: LocalDate?
    @AppStorage("weekCalendar.showsTimeline") private var showsTimeline = false
    /// The day the Timeline panel shows; today (or the week's first day) by default.
    @State private var timelineDay: LocalDate?

    public init(calendar: CalendarStore) {
        self.calendar = calendar
    }

    nonisolated static let hourHeight: CGFloat = 76
    nonisolated static let gutter: CGFloat = 44

    public var body: some View {
        // Redraw each minute, so meetings that just ended become loggable
        // and running timers grow.
        TimelineView(.everyMinute) { context in
            let start = weekStart ?? LocalDate().startOfWeek(firstWeekday: tracker.firstWeekday)
            let week = WeekModel(tracker: tracker, calendar: calendar, start: start, now: context.date)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(week)
                    if calendar.access != .granted { AccessBanner(calendar: calendar) }
                    dayHeaders(week)
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    ScrollView {
                        columns(week)
                            .padding(.bottom, 24)
                    }
                }
                if showsTimeline, let recorder {
                    Rectangle().fill(Color.hairline).frame(width: 1)
                    TimelinePanel(recorder: recorder, day: shownTimelineDay(week))
                        .frame(width: 300)
                }
            }
        }
        .background(Color.tileBackground)
        .tint(.harvestOrange)
        .task { await tracker.refresh() }
        .onChange(of: weekStart) { _, start in
            guard let start else { return }
            Task {
                await tracker.ensureLoaded(from: start)
                await tracker.ensureLoaded(through: start.adding(days: 6))
            }
        }
        // Calendar access may have been turned on in System Settings meanwhile.
        .onAppear { calendar.recheckAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendar.recheckAccess()
        }
    }

    private func header(_ week: WeekModel) -> some View {
        HStack(spacing: 12) {
            Text(week.title)
                .font(.system(size: 17, weight: .semibold))
            HStack(spacing: 0) {
                Button { move(by: -7, from: week.start) } label: { Image(systemName: "chevron.left").frame(width: 28, height: 26) }
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Previous week (⌘[)")
                Button { move(by: 7, from: week.start) } label: { Image(systemName: "chevron.right").frame(width: 28, height: 26) }
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Next week (⌘])")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .semibold))
            // Back to this week from anywhere; dimmed when you're already there.
            Button("This Week") { weekStart = nil }
                .buttonStyle(PillButtonStyle(prominent: false))
                .keyboardShortcut("t", modifiers: .command)
                .disabled(week.isThisWeek)
                .help("Back to this week (⌘T)")
            Spacer()
            if recorder != nil {
                Button { showsTimeline.toggle() } label: {
                    Label("Timeline", systemImage: "timeline.selection")
                }
                .buttonStyle(PillButtonStyle(prominent: false))
                .help(showsTimeline ? "Hide the Timeline" : "Show what you worked in, by time of day; click a day to choose it")
            }
            if !week.suggested.isEmpty {
                Text("From your calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("Log \(week.suggested.count) \(week.suggested.count == 1 ? "Meeting" : "Meetings") · \(TimeFormat.hoursMinutes(week.suggestedHours * 3600))") {
                    let meetings = week.suggested
                    Task { await tracker.logSuggested(meetings) }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .help("Log each blue meeting to the task it shows")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func dayHeaders(_ week: WeekModel) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(week.days) { day in
                let isTimelineDay = showsTimeline && shownTimelineDay(week) == day.date
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.title)
                        .font(.system(size: 13, weight: day.isToday ? .semibold : .medium))
                        .foregroundStyle(day.isToday ? AnyShapeStyle(.harvestOrange) : AnyShapeStyle(.primary))
                    Text(TimeFormat.hoursMinutes(day.loggedHours * 3600))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(isTimelineDay ? Color.orangeSoft : .clear).padding(.horizontal, 3))
                .contentShape(Rectangle())
                // Picks the day the Timeline shows.
                .onTapGesture { if recorder != nil { timelineDay = day.date } }
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("Week").font(.system(size: 13, weight: .semibold))
                Text(TimeFormat.hoursMinutes(week.loggedHours * 3600))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .trailing)
            .padding(.trailing, 18)
        }
        .padding(.bottom, 8)
    }

    private func columns(_ week: WeekModel) -> some View {
        // Tall enough for the fullest column as drawn: short items have a
        // minimum height, so a day of many quick entries runs past its hours.
        let hours = max(9, Int((week.tallestColumn / Self.hourHeight).rounded(.up)) + 1)
        return HStack(alignment: .top, spacing: 0) {
            // "1hr", "2hr"… down the side: how much time, not what time.
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(1...hours, id: \.self) { hour in
                    Text("\(hour)hr")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .frame(height: Self.hourHeight, alignment: .bottomTrailing)
                        .offset(y: 6)
                }
            }
            .frame(width: Self.gutter - 8, alignment: .trailing)
            .padding(.trailing, 8)

            ForEach(week.days) { day in
                VStack(spacing: 2) {
                    ForEach(day.items) { item in
                        switch item {
                        case .entry(let entry, _): EntryBlock(entry: entry)
                        case .meeting(let meeting, let status): MeetingBlock(meeting: meeting, status: status)
                        }
                    }
                }
                .padding(.horizontal, 3)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(day.isToday ? Color.orangeSoft.opacity(0.35) : Color.clear)
                .overlay(alignment: .leading) { Rectangle().fill(Color.hairline).frame(width: 1) }
            }
            Rectangle().fill(Color.hairline).frame(width: 1)
            Color.clear.frame(width: 82)
        }
        .frame(height: CGFloat(hours) * Self.hourHeight)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                ForEach(1...hours, id: \.self) { _ in
                    Color.clear.frame(height: Self.hourHeight - 1)
                    Rectangle().fill(Color.hairline.opacity(0.6)).frame(height: 1)
                }
            }
            .padding(.leading, Self.gutter)
        }
    }

    /// The chosen day if it's in this week, else today in this week, else its first day.
    private func shownTimelineDay(_ week: WeekModel) -> LocalDate {
        let days = week.days.map(\.date)
        if let timelineDay, days.contains(timelineDay) { return timelineDay }
        return days.first(where: { $0 == LocalDate() }) ?? week.start
    }

    private func move(by days: Int, from start: LocalDate) {
        let next = start.adding(days: days)
        weekStart = next == LocalDate().startOfWeek(firstWeekday: tracker.firstWeekday) ? nil : next
    }
}

// MARK: Model

/// One week's columns, worked out once per redraw.
@MainActor
struct WeekModel {
    struct Day: Identifiable {
        let date: LocalDate
        let title: String
        let isToday: Bool
        let items: [Item]
        let loggedHours: Double
        var id: LocalDate { date }
        /// The column's drawn height, meetings included, for sizing the grid.
        var stackedHeight: CGFloat {
            items.reduce(2) { total, item in
                switch item {
                case .entry(let entry, _): total + blockHeight(entry.elapsed() / 3600) + 2
                case .meeting(let meeting, _): total + blockHeight(meeting.hours) + 2
                }
            }
        }
    }

    enum Item: Identifiable {
        case entry(TimeEntry, sortedAt: Date)
        case meeting(CalendarMeeting, MeetingStatus)

        var id: String {
            switch self {
            case .entry(let entry, _): "entry-\(entry.id)"
            case .meeting(let meeting, _): "meeting-\(meeting.id)"
            }
        }

        var sortedAt: Date {
            switch self {
            case .entry(_, let date): date
            case .meeting(let meeting, _): meeting.start
            }
        }
    }

    let start: LocalDate
    let days: [Day]
    let suggested: [CalendarMeeting]
    let isThisWeek: Bool

    init(tracker: TimeTracker, calendar: CalendarStore, start: LocalDate, now: Date) {
        self.start = start
        let today = LocalDate(now)
        isThisWeek = start == today.startOfWeek(firstWeekday: tracker.firstWeekday)
        _ = calendar.revision // reload when the calendars change
        let meetings = calendar.meetings(from: start, through: start.adding(days: 6))
        var suggested: [CalendarMeeting] = []
        let formatter = Self.dayFormatter

        days = (0..<7).map { offset in
            let date = start.adding(days: offset)
            var items: [Item] = []
            // An entry made from a meeting sits where the meeting was.
            var meetingStarts: [Int: Date] = [:]
            for meeting in meetings where meeting.day == date {
                let status = tracker.status(of: meeting, at: now)
                if status == .logged {
                    if let entry = tracker.entry(for: meeting) { meetingStarts[entry.id] = meeting.start }
                    continue
                }
                if case .matched = status { suggested.append(meeting) }
                items.append(.meeting(meeting, status))
            }
            let entries = tracker.entries(on: date)
            for entry in entries {
                items.append(.entry(entry, sortedAt: meetingStarts[entry.id] ?? entry.timerStartedAt ?? entry.createdAt))
            }
            items.sort { $0.sortedAt < $1.sortedAt }
            return Day(
                date: date, title: formatter.string(from: date.date()), isToday: date == today, items: items,
                loggedHours: entries.reduce(0) { $0 + $1.elapsed(at: now) } / 3600
            )
        }
        self.suggested = suggested
    }

    var loggedHours: Double { days.reduce(0) { $0 + $1.loggedHours } }
    var suggestedHours: Double { suggested.reduce(0) { $0 + $1.hours } }
    var tallestColumn: CGFloat { days.map(\.stackedHeight).max() ?? 0 }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    var title: String {
        let formatter = Self.rangeFormatter
        return "\(formatter.string(from: start.date())) – \(formatter.string(from: start.adding(days: 6).date()))"
    }
}

// MARK: Blocks

private func blockHeight(_ hours: Double) -> CGFloat {
    max(CGFloat(hours) * WeekCalendarView.hourHeight - 2, 24)
}

/// A logged entry: orange, or dark with a clock while its timer runs.
private struct EntryBlock: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    @State private var isEditing = false
    @State private var isHovered = false

    var body: some View {
        let task = tracker.task(for: entry)
        let parts = task.projectNameParts
        let code = task.projectCode ?? parts.code
        let hours = entry.elapsed() / 3600
        Button {
            isEditing = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(code.map { "[\($0)] \(parts.name)" } ?? parts.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    if entry.lock != nil {
                        Image(systemName: "lock.fill").font(.system(size: 9))
                    }
                    Text(TimeFormat.hoursMinutes(entry.elapsed()))
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    if entry.isRunning {
                        Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                    }
                }
                if blockHeight(hours) >= 36 {
                    Text(entry.notes?.isEmpty == false ? entry.notes! : task.task.name)
                        .font(.system(size: 11))
                        .lineLimit(hours >= 1 ? 2 : 1)
                        .opacity(0.9)
                }
                if hours >= 1 {
                    Text(task.client?.name ?? "")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .opacity(0.7)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: blockHeight(hours), alignment: .top)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(entry.isRunning ? Color.adaptive(light: 0x333130, dark: 0x4A4541) : Color.harvestOrange)
                    .brightness(isHovered ? -0.05 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("\(task.task.name) · \(task.subtitle)")
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            if let lock = entry.lock {
                LockExplanation(lock: lock, day: entry.spentDate)
            } else {
                NewEntryEditor(day: entry.spentDate, entry: entry)
            }
        }
    }
}

/// A meeting not logged yet. Blue with its task when there's a match, a
/// dashed outline when it needs one, gray when skipped, faint until it ends.
private struct MeetingBlock: View {
    @Environment(TimeTracker.self) private var tracker
    let meeting: CalendarMeeting
    let status: MeetingStatus
    @State private var isLogging = false
    @State private var isHovered = false

    private var isUpcoming: Bool {
        if case .upcoming = status { return true }
        return false
    }

    var body: some View {
        Button {
            isLogging = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(meeting.hours >= 1 ? 2 : 1)
                    Spacer(minLength: 2)
                    Text(TimeFormat.hoursMinutes(meeting.hours * 3600))
                        .font(.system(size: 11.5).monospacedDigit())
                }
                if blockHeight(meeting.hours) >= 36 {
                    Text(caption)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .opacity(0.85)
                }
            }
            .foregroundStyle(status == .skipped ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.meetingText))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: blockHeight(meeting.hours), alignment: .top)
            .clipped()
            .background(background)
            .opacity(isUpcoming ? 0.65 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
        .contextMenu {
            if status == .skipped {
                Button("Don't Skip") { tracker.setSkipped(meeting, false) }
            } else {
                Button("Log Meeting…") { isLogging = true }
                Button("Skip") { tracker.setSkipped(meeting, true) }
            }
        }
        .popover(isPresented: $isLogging, arrowEdge: .trailing) {
            NewEntryEditor(day: meeting.day, meeting: meeting)
        }
    }

    private var caption: String {
        switch status {
        case .matched(let suggestion), .upcoming(let suggestion?):
            let parts = suggestion.task.projectNameParts
            return "→ " + ((suggestion.task.projectCode ?? parts.code).map { "[\($0)] " } ?? "") + parts.name
        case .unmatched, .upcoming(nil): return "Choose a task…"
        case .skipped: return "Skipped"
        case .logged: return ""
        }
    }

    private var help: String {
        switch status {
        case .matched(let suggestion): "\(suggestion.explanation). Click to log it."
        case .unmatched: "Click to pick a task and log it"
        case .skipped: "Skipped. Click to log it anyway."
        case .upcoming: "Hasn't happened yet. Click to log it ahead of time."
        case .logged: ""
        }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch status {
        case .unmatched, .upcoming(nil):
            shape.fill(Color.meetingFill.opacity(isHovered ? 0.5 : 0.25))
                .overlay(shape.strokeBorder(Color.meetingText.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
        case .skipped:
            shape.fill(Color.primary.opacity(isHovered ? 0.09 : 0.05))
        default:
            shape.fill(Color.meetingFill).brightness(isHovered ? -0.04 : 0)
        }
    }
}

// MARK: Timeline

/// One day of the Timeline by time of day, like Toggl's: thin bars for each
/// app and window (orange while a timer ran), and the stretches no timer
/// covered as boxes you can click to log.
private struct TimelinePanel: View {
    @Environment(TimeTracker.self) private var tracker
    let recorder: ActivityRecorder
    let day: LocalDate
    @AppStorage(ActivityRecorder.timelineKey) private var isRecording = false

    static let hourHeight: CGFloat = 64

    var body: some View {
        let spans = recorder.spans(on: day)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline").font(.system(size: 15, weight: .semibold))
                Text(day.date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            if !isRecording {
                note("Timeline is off", "Turn on “Record my Timeline” in Preferences → Tracking. It notes the apps and windows you use, kept on this Mac for two weeks.")
            } else if !ActivityRecorder.hasAccessibility {
                note("Window titles need Accessibility", "Without it, only app names are recorded.", button: "Allow…") {
                    ActivityRecorder.requestAccessibility()
                }
            }
            if spans.isEmpty {
                Text(isRecording ? "Nothing recorded on this day yet." : "")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                Spacer()
            } else {
                ScrollView { clock(spans).padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 20) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.panelBackground)
    }

    private func clock(_ spans: [ActivitySpan]) -> some View {
        let calendar = Calendar.current
        let firstHour = calendar.component(.hour, from: spans.map(\.start).min()!)
        let lastHour = min(24, calendar.component(.hour, from: spans.map(\.end).max()!) + 1)
        let origin = calendar.date(bySettingHour: firstHour, minute: 0, second: 0, of: day.date())!
        func y(_ date: Date) -> CGFloat { CGFloat(date.timeIntervalSince(origin) / 3600) * Self.hourHeight }
        // Stretch boxes sit at their start, nudged down so they never overlap.
        var bottom: CGFloat = -.infinity
        let boxes = Timeline.untrackedStretches(spans).map { stretch -> (ActivityStretch, CGFloat) in
            let top = max(y(stretch.start), bottom + 4)
            bottom = top + 58
            return (stretch, top)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(firstHour...lastHour, id: \.self) { hour in
                HStack(spacing: 6) {
                    Text(calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now)!.formatted(.dateTime.hour()))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 34, alignment: .trailing)
                    Rectangle().fill(Color.hairline).frame(height: 1)
                }
                .offset(y: CGFloat(hour - firstHour) * Self.hourHeight - 6)
            }
            ForEach(spans) { span in
                RoundedRectangle(cornerRadius: 2)
                    .fill(span.trackedKey == nil ? Color.primary.opacity(0.28) : Color.harvestOrange)
                    .frame(width: 10, height: max(2, y(span.end) - y(span.start)))
                    .offset(x: 42, y: y(span.start))
                    .help("\(span.start.formatted(date: .omitted, time: .shortened)) · \(TimeFormat.hoursMinutes(span.seconds)) · \(span.label)"
                          + (span.trackedKey.flatMap { tracker.tasks(for: [$0]).first }.map { "\nTracked: \($0.projectNameParts.name) · \($0.task.name)" } ?? ""))
            }
            ForEach(boxes, id: \.0.id) { stretch, top in
                StretchBox(stretch: stretch, day: day)
                    .padding(.leading, 60)
                    .offset(y: top)
            }
        }
        .frame(maxWidth: .infinity, minHeight: max(CGFloat(lastHour - firstHour) * Self.hourHeight, bottom + 8), alignment: .topLeading)
    }

    private func note(_ title: String, _ detail: String, button: String? = nil, action: @escaping () -> Void = {}) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let button { Button(button, action: action).buttonStyle(PillButtonStyle(prominent: false)) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.tileBackground))
        .padding(.horizontal, 12)
    }
}

/// A stretch no timer covered: how long, what it was mostly, and the task it
/// points to. Click to log it.
private struct StretchBox: View {
    @Environment(TimeTracker.self) private var tracker
    let stretch: ActivityStretch
    let day: LocalDate
    @State private var isLogging = false

    var body: some View {
        let item = stretch.asMeeting
        let status = tracker.status(of: item)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        Button { isLogging = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(TimeFormat.hoursMinutes(stretch.seconds)) not tracked")
                        .font(.system(size: 11.5, weight: .semibold))
                    Spacer(minLength: 4)
                    Text(stretch.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Text(stretch.topLabels.prefix(2).joined(separator: ", "))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text(caption(status))
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(Color.meetingText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
            .background(shape.fill(status == .logged ? Color.primary.opacity(0.04) : Color.meetingFill.opacity(0.35)))
            .overlay(shape.strokeBorder(Color.meetingText.opacity(status == .logged ? 0.15 : 0.5), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(status == .logged)
        .opacity(status == .logged || status == .skipped ? 0.55 : 1)
        .contextMenu {
            if status == .skipped {
                Button("Don't Skip") { tracker.setSkipped(item, false) }
            } else if status != .logged {
                Button("Log Activity…") { isLogging = true }
                Button("Skip") { tracker.setSkipped(item, true) }
            }
        }
        .popover(isPresented: $isLogging, arrowEdge: .leading) { NewEntryEditor(day: day, meeting: item) }
    }

    private func caption(_ status: MeetingStatus) -> String {
        switch status {
        case .logged: "Logged"
        case .skipped: "Skipped"
        case .matched(let match), .upcoming(let match?):
            "→ " + ((match.task.projectCode ?? match.task.projectNameParts.code).map { "[\($0)] " } ?? "") + match.task.projectNameParts.name
        case .unmatched, .upcoming(nil): "Choose a task…"
        }
    }
}

/// Asks for calendar access, or says where to turn it back on.
private struct AccessBanner: View {
    let calendar: CalendarStore
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.meetingText)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            switch calendar.access {
            case .notAsked:
                Button("Show My Meetings") { Task { await calendar.requestAccess() } }
                    .buttonStyle(PillButtonStyle(prominent: true))
            case .denied:
                Button("Open Privacy Settings") {
                    openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
                .buttonStyle(PillButtonStyle(prominent: false))
            default:
                EmptyView()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.meetingFill.opacity(0.45)))
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var title: String {
        switch calendar.access {
        case .denied: "Calendar access is off"
        case .unavailable: "Calendar needs the installed app"
        default: "See your meetings here, and log them in a click"
        }
    }

    private var detail: String {
        switch calendar.access {
        case .denied: "Turn on Harvestbeam under Calendars in Privacy & Security, then come back."
        case .unavailable: "Run Harvestbeam from Applications to read your calendar."
        default: "Harvestbeam reads your calendar on this Mac to suggest entries. Nothing is logged until you say so."
        }
    }
}

#if DEBUG
/// For offscreen snapshots of the week calendar with demo meetings.
@MainActor public func debugWeekCalendar() -> some View { WeekCalendarView(calendar: .demo()) }

/// The week calendar with the Timeline open on a made-up morning.
@MainActor public func debugWeekCalendarWithTimeline(_ tracker: TimeTracker) -> some View {
    UserDefaults.standard.set(true, forKey: "weekCalendar.showsTimeline")
    let store = TimelineStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("HarvestbeamTimelineDemo-\(UUID())"))
    let day = LocalDate().date()
    let tracked = tracker.tasks.first?.key
    func span(_ from: Double, _ to: Double, _ app: String, _ title: String, host: String? = nil, tracked key: TaskKey? = nil) {
        store.append(ActivitySpan(app: app, bundleID: app, title: title, host: host,
                                  start: day.addingTimeInterval(from * 3600), end: day.addingTimeInterval(to * 3600), trackedKey: key))
    }
    span(9, 9.6, "Figma", "Website Redesign – Homepage", tracked: tracked)
    span(9.6, 9.9, "Google Chrome", "Campaigns", host: "ads.google.com")
    span(9.9, 10.3, "Mail", "Re: Acme Co brand review")
    span(10.3, 11.4, "Xcode", "harvest-bar", tracked: tracked)
    span(11.4, 11.75, "Slack", "#acme-co")
    span(13, 13.5, "Google Chrome", "Northwind dashboard", host: "lookerstudio.google.com")
    return WeekCalendarView(calendar: .demo()).environment(ActivityRecorder(tracker: tracker, store: store))
}

/// The Log Meeting popover for the demo week's first matched meeting.
@MainActor public func debugMeetingEditor() -> some View {
    let start = LocalDate().startOfWeek(firstWeekday: 2).date().addingTimeInterval(11 * 3600)
    let meeting = CalendarMeeting(id: "debug", title: "Acme Co brand review", start: start, end: start.addingTimeInterval(3600))
    return NewEntryEditor(day: meeting.day, meeting: meeting)
}
#endif
#endif
