#if os(macOS)
import HarvestKit
import SwiftUI

/// Opens the Week Review sheet over the window: from the ⋯ menu, or the
/// Friday reminder's notification.
@MainActor @Observable
public final class WeekReviewPresenter {
    public static let shared = WeekReviewPresenter()
    public var isPresented = false
    public init() {}
}

/// The day and moment the review is as of; real time unless a snapshot sets it.
public struct ReviewClock: Sendable {
    public var today: LocalDate
    public var now: Date
    public init(today: LocalDate, now: Date) {
        self.today = today
        self.now = now
    }
}

private struct ReviewClockKey: EnvironmentKey {
    static let defaultValue: ReviewClock? = nil
}

public extension EnvironmentValues {
    var reviewClock: ReviewClock? {
        get { self[ReviewClockKey.self] }
        set { self[ReviewClockKey.self] = newValue }
    }
}

public extension View {
    /// Presents the Week Review when `WeekReviewPresenter.shared` asks;
    /// "Open Day" lands on `selectedDay`.
    func weekReviewSheet(selectedDay: Binding<LocalDate>) -> some View {
        modifier(WeekReviewSheet(selectedDay: selectedDay))
    }
}

private struct WeekReviewSheet: ViewModifier {
    @Environment(TimeTracker.self) private var tracker
    @Environment(CalendarStore.self) private var calendar: CalendarStore?
    @Environment(ActivityRecorder.self) private var recorder: ActivityRecorder?
    @Environment(\.windowActions) private var windowActions
    @Bindable private var presenter = WeekReviewPresenter.shared
    @Binding var selectedDay: LocalDate

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presenter.isPresented) {
            WeekReviewView { day in
                presenter.isPresented = false
                withAnimation(.snappy(duration: 0.2)) { selectedDay = day }
            }
            .environment(tracker)
            .environment(calendar)
            .environment(recorder)
            .environment(\.windowActions, windowActions)
        }
    }
}

// MARK: Gap fixes

/// The best one-click way to fill a gap: a meeting that was on, the task the
/// app you were in points to, or just the entry editor.
enum GapFix {
    case meeting(CalendarMeeting, MeetingSuggestion?)
    case activity(ScreenContext, MeetingSuggestion)
    case manual

    @MainActor static func best(for gap: TimeGap, tracker: TimeTracker, calendar: CalendarStore?, recorder: ActivityRecorder?) -> GapFix {
        let meetings = calendar?.meetings(from: gap.day, through: gap.day) ?? []
        let open = GapFinder.meetings(overlapping: gap, in: meetings).filter { meeting in
            switch tracker.status(of: meeting) {
            case .logged, .skipped: false
            default: true
            }
        }
        if let meeting = open.first {
            let suggestion = tracker.meetingSuggestion(for: meeting).flatMap { tracker.isAvailable($0.task.key) ? $0 : nil }
            return .meeting(meeting, suggestion)
        }
        if let recorder, let top = GapFinder.topActivity(in: gap, spans: recorder.spans(on: gap.day)),
           let suggestion = tracker.suggestion(for: top.context), tracker.isAvailable(suggestion.task.key),
           !RetiredBuckets.isRetired(suggestion.task) {
            return .activity(top.context, suggestion)
        }
        return .manual
    }
}

/// "Log Acme sync (meeting)" or "Log to Website Redesign (Figma)", then
/// "Log…", for a gap.
struct GapFixButtons: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(CalendarStore.self) private var calendar: CalendarStore?
    @Environment(ActivityRecorder.self) private var recorder: ActivityRecorder?
    let gap: TimeGap
    @State private var isLogging = false
    @State private var meetingToLog: CalendarMeeting?

    var body: some View {
        HStack(spacing: 6) {
            switch GapFix.best(for: gap, tracker: tracker, calendar: calendar, recorder: recorder) {
            case .meeting(let meeting, let suggestion):
                Button {
                    if let suggestion {
                        Task {
                            await tracker.log(meeting, task: suggestion.task, notes: meeting.title, hours: meeting.hours,
                                              remember: suggestion.reason == .remembered)
                        }
                    } else {
                        meetingToLog = meeting
                    }
                } label: {
                    Label("Log \(meeting.title) (meeting)" + (suggestion == nil ? "…" : ""), systemImage: "calendar")
                        .lineLimit(1)
                }
                .buttonStyle(ReviewFixButtonStyle(prominent: true))
                .help(suggestion.map { "Logs \(TimeFormat.hoursMinutes(meeting.hours * 3600)) to \($0.task.projectNameParts.name) · \($0.task.task.name). \($0.explanation)" }
                      ?? "Pick the task this meeting belongs to")
                .popover(item: $meetingToLog, arrowEdge: .bottom) { NewEntryEditor(day: $0.day, meeting: $0) }
            case .activity(let context, let suggestion):
                Button {
                    Task {
                        await tracker.addEntry(task: suggestion.task, on: gap.day, notes: context.title.isEmpty ? context.app : context.title,
                                               hours: gap.hours, startingAt: gap.interval().start)
                    }
                } label: {
                    Label("Log to \(suggestion.task.projectNameParts.name) (\(context.app))", systemImage: "macwindow")
                        .lineLimit(1)
                }
                .buttonStyle(ReviewFixButtonStyle(prominent: true))
                .help("You were mostly in \(context.app) then. Logs \(TimeFormat.hoursMinutes(gap.hours * 3600)) to \(suggestion.task.projectNameParts.name) · \(suggestion.task.task.name).")
            case .manual:
                EmptyView()
            }
            Button("Log…") { isLogging = true }
                .buttonStyle(ReviewFixButtonStyle(prominent: false))
                .help("Log \(gap.fullLabel) to any task")
                .popover(isPresented: $isLogging, arrowEdge: .bottom) { NewEntryEditor(day: gap.day, gap: gap) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Small pill buttons for fixes: orange for the suggested fix, quiet otherwise.
struct ReviewFixButtonStyle: ButtonStyle {
    var prominent: Bool
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(prominent ? (isHovered ? AnyShapeStyle(.white) : AnyShapeStyle(.harvestOrange)) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(prominent ? (isHovered ? Color.harvestOrange : Color.orangeSoft)
                                                 : Color.primary.opacity(isHovered ? 0.12 : 0.07)))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// An "×" that says a gap wasn't work, so it stops coming up.
private struct IgnoreGapButton: View {
    let gap: TimeGap
    @AppStorage(WeekReview.ignoredGapsKey) private var ignoredRaw = ""

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { WeekReview.ignore(gap) }
            // Nudge @AppStorage watchers; `ignore` already saved it.
            ignoredRaw = UserDefaults.standard.string(forKey: WeekReview.ignoredGapsKey) ?? ignoredRaw
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Not work time (lunch, a break): stop showing it")
        .accessibilityLabel("Not work time, dismiss")
    }
}

// MARK: The day's gap rows

/// "1:00–2:30 not logged" rows at the foot of a day's entries, on accounts
/// that track start and end times.
struct DayGapRows: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.reviewClock) private var clock
    @AppStorage(WeekReview.ignoredGapsKey) private var ignoredRaw = ""
    let day: LocalDate

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = clock?.now ?? context.date
            let gaps = tracker.gaps(on: day, today: clock?.today ?? LocalDate(now), now: now)
            let _ = ignoredRaw
            VStack(spacing: 0) {
                ForEach(gaps) { gap in
                    Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, 14)
                    GapRow(gap: gap)
                }
            }
        }
    }
}

private struct GapRow: View {
    let gap: TimeGap
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                Text("\(gap.label) not logged")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(TimeFormat.hoursMinutes(gap.hours * 3600))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 6)
                IgnoreGapButton(gap: gap)
                    .opacity(isHovered ? 1 : 0.5)
            }
            GapFixButtons(gap: gap)
                .padding(.leading, 22)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .background(Color.primary.opacity(0.018))
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(gap.fullLabel) not logged")
    }
}

// MARK: The sheet

/// What needs attention before the week closes, each with a fix.
struct WeekReviewView: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(CalendarStore.self) private var calendar: CalendarStore?
    @Environment(\.windowActions) private var windowActions
    @Environment(\.reviewClock) private var clock
    @Environment(\.dismiss) private var dismiss
    @AppStorage(WeekReview.ignoredGapsKey) private var ignoredRaw = ""
    var onOpenDay: (LocalDate) -> Void
    /// Snapshots only: show these instead of working them out.
    var itemsOverride: [ReviewItem]?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = clock?.now ?? context.date
            let today = clock?.today ?? LocalDate(now)
            let _ = ignoredRaw
            let items = itemsOverride ?? tracker.weekReview(today: today, now: now)
            VStack(spacing: 0) {
                header(items: items, today: today)
                Divider()
                if items.isEmpty {
                    allSet
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(items.filter { if case .staleTimer = $0 { true } else { false } }) { item in
                                if case .staleTimer(let entry) = item { StaleTimerCard(entry: entry, now: now) }
                            }
                            ForEach(days(in: items), id: \.self) { day in
                                DaySection(day: day, today: today, now: now,
                                           items: items.filter { $0.day == day && !$0.isStaleTimer },
                                           onOpenDay: onOpenDay)
                            }
                        }
                        .padding(18)
                    }
                }
            }
        }
        .frame(idealWidth: 420, maxWidth: 500)
        .frame(minHeight: 420, idealHeight: 620, maxHeight: 760)
        .background(Color.panelBackground)
        .tint(.harvestOrange)
    }

    private func days(in items: [ReviewItem]) -> [LocalDate] {
        var seen = Set<LocalDate>()
        return items.filter { !$0.isStaleTimer }.map(\.day).filter { seen.insert($0).inserted }
    }

    private func header(items: [ReviewItem], today: LocalDate) -> some View {
        let deadline = WeekReview.deadline(containing: today, firstWeekday: tracker.firstWeekday)
        let local = deadline.formatted(date: .omitted, time: .shortened)
        let sameZone = TimeZone.current.secondsFromGMT(for: deadline) == WeekReview.central.secondsFromGMT(for: deadline)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Week Review")
                    .font(.system(size: 17, weight: .semibold))
                Text("Your week closes Friday at 6:00 PM Central" + (sameZone ? "." : " (\(local) here)."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if !items.isEmpty {
                    Text(items.count == 1 ? "1 thing to sort out" : "\(items.count) things to sort out")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color.shortDay)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.shortDayFill))
                        .padding(.top, 5)
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(PillButtonStyle(prominent: items.isEmpty))
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var allSet: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.reviewGreen)
            Text("All set for this week ✓")
                .font(.system(size: 16, weight: .semibold))
            Text("Every workday is logged, noted and on a current task.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ReviewItem {
    var isStaleTimer: Bool { if case .staleTimer = self { true } else { false } }
}

extension Color {
    static var reviewGreen: Color { .adaptive(light: 0x2E8B57, dark: 0x5CC98A) }
}

private struct StaleTimerCard: View {
    @Environment(TimeTracker.self) private var tracker
    let entry: TimeEntry
    let now: Date

    var body: some View {
        let task = tracker.task(for: entry)
        let weekday = entry.spentDate.date().formatted(.dateTime.weekday(.wide))
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.harvestOrange)
            VStack(alignment: .leading, spacing: 1) {
                Text("A timer from \(weekday) is still running")
                    .font(.system(size: 12.5, weight: .semibold))
                Text("\(task.projectNameParts.name) · \(task.task.name) · \(TimeFormat.hoursMinutes(entry.elapsed(at: now)))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            Button("Pause Timer") { Task { await tracker.pause() } }
                .buttonStyle(ReviewFixButtonStyle(prominent: true))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Metrics.tileCorner, style: .continuous).fill(Color.orangeSoft))
    }
}

private struct DaySection: View {
    @Environment(TimeTracker.self) private var tracker
    let day: LocalDate
    let today: LocalDate
    let now: Date
    let items: [ReviewItem]
    let onOpenDay: (LocalDate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(day.dayTitle(today: today))
                    .font(.system(size: 13, weight: .semibold))
                Text("\(TimeFormat.hoursMinutes(tracker.seconds(on: day, at: now))) of \(TimeFormat.hoursMinutes(tracker.usualDaySeconds))")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 38) }
                    ReviewRow(item: item, today: today, onOpenDay: onOpenDay)
                }
            }
            .background(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).fill(Color.tileBackground))
            .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.cardCorner, style: .continuous).strokeBorder(Color.hairline))
        }
    }
}

private struct ReviewRow: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(CalendarStore.self) private var calendar: CalendarStore?
    @Environment(\.windowActions) private var windowActions
    let item: ReviewItem
    let today: LocalDate
    let onOpenDay: (LocalDate) -> Void
    @State private var note = ""
    @State private var isEditing = false

    var body: some View {
        HStack(alignment: isTwoLine ? .top : .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)
                .padding(.top, isTwoLine ? 2 : 0)
            content
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 46)
    }

    private var isTwoLine: Bool {
        switch item {
        case .gap, .missingNotes: true
        default: false
        }
    }

    private var icon: String {
        switch item {
        case .staleTimer: "timer"
        case .emptyDay: "calendar.badge.exclamationmark"
        case .shortDay: "clock.badge.exclamationmark"
        case .gap: "clock.badge.questionmark"
        case .retiredBucket: "archivebox"
        case .missingNotes: "text.bubble"
        }
    }

    private var iconColor: Color {
        switch item {
        case .emptyDay, .shortDay: .shortDay
        case .retiredBucket: .archivedTint
        default: .secondary
        }
    }

    @ViewBuilder private var content: some View {
        switch item {
        case .staleTimer:
            EmptyView()
        case .emptyDay(let day):
            title("Nothing logged", detail: nil)
            Spacer(minLength: 6)
            let matched = (calendar?.meetings(from: day, through: day) ?? []).filter {
                if case .matched = tracker.status(of: $0) { true } else { false }
            }
            if !matched.isEmpty {
                Button(matched.count == 1 ? "Log 1 Meeting" : "Log \(matched.count) Meetings") {
                    Task { await tracker.logSuggested(matched) }
                }
                .buttonStyle(ReviewFixButtonStyle(prominent: true))
                .help(matched.map(\.title).joined(separator: ", "))
            } else if let openWeek = windowActions?.openWeekCalendar {
                Button("Week Calendar") { openWeek() }
                    .buttonStyle(ReviewFixButtonStyle(prominent: false))
                    .help("Log from your calendar")
            }
            Button("Open Day") { onOpenDay(day) }
                .buttonStyle(ReviewFixButtonStyle(prominent: matched.isEmpty))
        case .shortDay(_, let logged, let usual):
            title("\(TimeFormat.hoursMinutes(usual - logged)) short of a usual day", detail: "Only \(TimeFormat.hoursMinutes(logged)) logged")
            Spacer(minLength: 6)
            Button("Open Day") { onOpenDay(item.day) }
                .buttonStyle(ReviewFixButtonStyle(prominent: false))
        case .gap(let gap):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    title("\(gap.label) not logged", detail: TimeFormat.hoursMinutes(gap.hours * 3600))
                    Spacer(minLength: 6)
                    IgnoreGapButton(gap: gap)
                }
                GapFixButtons(gap: gap)
            }
        case .retiredBucket(let entry):
            retired(entry)
        case .missingNotes(let entry):
            missingNotes(entry)
        }
    }

    private func title(_ text: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
            if let detail {
                Text(detail)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    private func entryTitle(_ entry: TimeEntry) -> some View {
        let task = tracker.task(for: entry)
        return VStack(alignment: .leading, spacing: 1) {
            Text("\(task.projectNameParts.name) · \(task.task.name)")
                .font(.system(size: 12.5, weight: .medium))
            Text([entry.startedTime.flatMap { start in entry.endedTime.map { "\(start)–\($0)" } },
                  TimeFormat.hoursMinutes(entry.elapsed()), entry.notes.flatMap { $0.isEmpty ? nil : $0 }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    @ViewBuilder private func retired(_ entry: TimeEntry) -> some View {
        entryTitle(entry)
        StatusTagLabel(text: "Retired")
        Spacer(minLength: 6)
        Menu {
            let choices = moveChoices(excluding: entry.key)
            if choices.isEmpty { Text("No recent tasks") }
            ForEach(choices) { task in
                Button("\(task.projectNameParts.name) · \(task.task.name)") {
                    Task { await tracker.updateEntry(entry, task: task, notes: entry.notes ?? "", hours: nil) }
                }
            }
            Divider()
            Button("Another Task…") { isEditing = true }
        } label: {
            Text("Move to…")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .font(.system(size: 11.5, weight: .semibold))
        .help("This bucket is retired. Move the time to the task it belongs to.")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) { NewEntryEditor(day: entry.spentDate, entry: entry) }
    }

    /// Recent, favorite and suggested tasks you can still log to.
    private func moveChoices(excluding key: TaskKey) -> [TrackableTask] {
        var seen = Set<TaskKey>([key])
        return (tracker.recentTasks + tracker.favoriteTasks + tracker.suggestedTasks)
            .filter { tracker.isAvailable($0.key) && !RetiredBuckets.isRetired($0) && seen.insert($0.key).inserted }
            .prefix(8).map { $0 }
    }

    @ViewBuilder private func missingNotes(_ entry: TimeEntry) -> some View {
        let task = tracker.task(for: entry)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(task.projectNameParts.name) · \(task.task.name)")
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(TimeFormat.hoursMinutes(entry.elapsed()))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                TextField("Add a note", text: $note, prompt: Text("Add a note…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.panelBackground.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                    .onSubmit { save(entry) }
                Button("Save") { save(entry) }
                    .buttonStyle(ReviewFixButtonStyle(prominent: true))
                    .disabled(note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save(_ entry: TimeEntry) {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await tracker.updateEntry(entry, task: tracker.task(for: entry), notes: text, hours: nil) }
    }
}

/// A small "Retired" tag, like the Archived one on entries.
private struct StatusTagLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.archivedTint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.archivedTint.opacity(0.14)))
            .fixedSize()
    }
}

#if DEBUG
/// For offscreen snapshots: the review as of `now`, with the demo calendar
/// and a made-up Timeline under one of the gaps.
@MainActor public func debugWeekReview(_ tracker: TimeTracker, today: LocalDate, now: Date) -> some View {
    WeekReviewView(onOpenDay: { _ in })
        .environment(\.reviewClock, ReviewClock(today: today, now: now))
        .environment(CalendarStore.demo(now: now))
        .environment(debugGapTimeline(tracker, monday: today.startOfWeek(firstWeekday: 2)))
}

/// For offscreen snapshots: nothing left to fix.
@MainActor public func debugWeekReviewAllSet() -> some View {
    WeekReviewView(onOpenDay: { _ in }, itemsOverride: [])
}

/// For offscreen snapshots: a day's entries with its gap rows.
@MainActor public func debugDayWithGaps(_ tracker: TimeTracker, day: LocalDate, today: LocalDate, now: Date) -> some View {
    debugArchivedDays([day], explaining: nil)
        .environment(\.reviewClock, ReviewClock(today: today, now: now))
        .environment(CalendarStore.demo(now: now))
        .environment(debugGapTimeline(tracker, monday: today.startOfWeek(firstWeekday: 2)))
}

/// Tuesday afternoon in Figma on the website, with nothing logged.
@MainActor private func debugGapTimeline(_ tracker: TimeTracker, monday: LocalDate) -> ActivityRecorder {
    let store = TimelineStore(folder: FileManager.default.temporaryDirectory.appendingPathComponent("HarvestbeamReviewDemo-\(UUID())"))
    let tuesday = monday.adding(days: 1).date()
    store.append(ActivitySpan(app: "Figma", bundleID: "com.figma.Desktop", title: "Website Redesign – Nav states",
                              start: tuesday.addingTimeInterval(15.6 * 3600), end: tuesday.addingTimeInterval(16.9 * 3600)))
    store.append(ActivitySpan(app: "Slack", bundleID: "com.tinyspeck.slackmacgap", title: "#design",
                              start: tuesday.addingTimeInterval(16.9 * 3600), end: tuesday.addingTimeInterval(17.1 * 3600)))
    return ActivityRecorder(tracker: tracker, store: store)
}
#endif
#endif
