import Foundation

// MARK: Gaps

/// Unlogged time in a workday, on accounts that track start and end times:
/// "1:00–2:30 not logged".
public struct TimeGap: Hashable, Sendable, Identifiable {
    public let day: LocalDate
    /// Minutes after midnight.
    public let start: Int
    public let end: Int

    public init(day: LocalDate, start: Int, end: Int) {
        self.day = day
        self.start = start
        self.end = end
    }

    public var id: String { "\(day)@\(start)-\(end)" }
    public var minutes: Int { end - start }
    public var hours: Double { Double(minutes) / 60 }

    /// "1:00–2:30", the way the day list writes it; working hours make
    /// am and pm plain.
    public var label: String { "\(Self.short(start))–\(Self.short(end))" }

    /// "1:00pm–2:30pm", for VoiceOver and the entry editor.
    public var fullLabel: String { "\(ClockTime.format(start))–\(ClockTime.format(end))" }

    private static func short(_ minutes: Int) -> String {
        let hour = minutes / 60 % 12
        return String(format: "%d:%02d", hour == 0 ? 12 : hour, minutes % 60)
    }

    /// When it starts and ends on the clock.
    public func interval(calendar: Calendar = .current) -> DateInterval {
        let midnight = day.date(in: calendar)
        let from = calendar.date(byAdding: .minute, value: start, to: midnight) ?? midnight
        let to = calendar.date(byAdding: .minute, value: end, to: midnight) ?? midnight
        return DateInterval(start: from, end: max(from, to))
    }
}

public enum GapFinder {
    /// Shorter breaks aren't worth asking about.
    public static let minimumMinutes = 20
    /// 9:00 to 6:00, unless Preferences say otherwise.
    public static let defaultWorkday = 9 * 60..<18 * 60
    public static let workStartKey = "review.workStart"
    public static let workEndKey = "review.workEnd"

    /// Working hours from preferences, as minutes after midnight.
    public static func workday(_ defaults: UserDefaults = .standard) -> Range<Int> {
        let start = defaults.object(forKey: workStartKey) as? Int ?? defaultWorkday.lowerBound
        let end = defaults.object(forKey: workEndKey) as? Int ?? defaultWorkday.upperBound
        return end > start ? start..<end : defaultWorkday
    }

    /// The minutes an entry covers on its day. A running timer (or one with no
    /// end written yet) runs from its start for as long as it's tracked so far.
    /// Nil for entries with no start time.
    public static func span(of entry: TimeEntry, at now: Date = .now) -> Range<Int>? {
        guard let start = entry.startedTime.flatMap(ClockTime.minutes) else { return nil }
        if !entry.isRunning, let end = entry.endedTime.flatMap(ClockTime.minutes), end > start {
            return start..<end
        }
        let length = max(1, Int((entry.elapsed(at: now) / 60).rounded()))
        return start..<min(24 * 60, start + length)
    }

    /// Stretches of `workday` that nothing covers, at least `minimum` long.
    /// `until` cuts the day short (today: now).
    public static func gaps(
        day: LocalDate, covered: [Range<Int>], workday: Range<Int> = defaultWorkday,
        until: Int? = nil, minimum: Int = minimumMinutes
    ) -> [TimeGap] {
        let end = min(workday.upperBound, until ?? .max)
        guard end > workday.lowerBound else { return [] }
        var cursor = workday.lowerBound
        var gaps: [TimeGap] = []
        for range in covered.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if cursor >= end { break }
            let gapEnd = min(range.lowerBound, end)
            if gapEnd - cursor >= minimum { gaps.append(TimeGap(day: day, start: cursor, end: gapEnd)) }
            cursor = max(cursor, range.upperBound)
        }
        if end - cursor >= minimum { gaps.append(TimeGap(day: day, start: cursor, end: end)) }
        return gaps
    }

    /// A day's gaps from its entries.
    public static func gaps(
        day: LocalDate, entries: [TimeEntry], workday: Range<Int> = defaultWorkday,
        until: Int? = nil, now: Date = .now, minimum: Int = minimumMinutes
    ) -> [TimeGap] {
        let covered = entries.filter { $0.spentDate == day }.compactMap { span(of: $0, at: now) }
        return gaps(day: day, covered: covered, workday: workday, until: until, minimum: minimum)
    }

    /// Meetings that overlap the gap by ten minutes or more, most overlap first.
    public static func meetings(overlapping gap: TimeGap, in meetings: [CalendarMeeting], calendar: Calendar = .current) -> [CalendarMeeting] {
        let span = gap.interval(calendar: calendar)
        func overlap(_ meeting: CalendarMeeting) -> TimeInterval {
            max(0, min(span.end, meeting.end).timeIntervalSince(max(span.start, meeting.start)))
        }
        return meetings
            .filter { !$0.isActivity && overlap($0) >= 10 * 60 }
            .sorted { overlap($0) != overlap($1) ? overlap($0) > overlap($1) : $0.start < $1.start }
    }

    /// The app you spent the most untracked time in during the gap (five
    /// minutes at least), and its busiest window for matching to a task.
    public static func topActivity(
        in gap: TimeGap, spans: [ActivitySpan], calendar: Calendar = .current
    ) -> (context: ScreenContext, seconds: TimeInterval)? {
        let window = gap.interval(calendar: calendar)
        var byApp: [String: TimeInterval] = [:]
        var busiest: [String: (span: ActivitySpan, seconds: TimeInterval)] = [:]
        for span in spans where span.trackedKey == nil {
            let seconds = min(window.end, span.end).timeIntervalSince(max(window.start, span.start))
            guard seconds > 0 else { continue }
            byApp[span.bundleID, default: 0] += seconds
            if seconds > (busiest[span.bundleID]?.seconds ?? 0) { busiest[span.bundleID] = (span, seconds) }
        }
        guard let top = byApp.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
              top.value >= 5 * 60, let span = busiest[top.key]?.span else { return nil }
        return (ScreenContext(app: span.app, bundleID: span.bundleID, title: span.title, host: span.host), top.value)
    }
}

// MARK: Retired buckets

/// Buckets the team no longer logs to: the generic "Digital Products" bucket
/// and the legacy "Business Dev" one. Matched on the project or task name,
/// ignoring a leading "[CODE]", case and accents.
public enum RetiredBuckets {
    public static func isRetired(project: String, task: String) -> Bool {
        [project, task].contains { name in
            let n = MeetingMatcher.normalized(stripCode(name))
            if n == "digital products" || (n.contains("digital products") && n.contains("generic")) { return true }
            if n == "business dev" || n == "business dev." || (n.contains("business dev") && n.contains("legacy")) { return true }
            return false
        }
    }

    public static func isRetired(_ entry: TimeEntry) -> Bool {
        isRetired(project: entry.project.name, task: entry.task.name)
    }

    public static func isRetired(_ task: TrackableTask) -> Bool {
        isRetired(project: task.project.name, task: task.task.name)
    }

    private static func stripCode(_ name: String) -> String {
        guard name.hasPrefix("["), let close = name.firstIndex(of: "]") else { return name }
        return String(name[name.index(after: close)...])
    }
}

// MARK: The review

/// Something to sort out before the week closes.
public enum ReviewItem: Hashable, Sendable, Identifiable {
    /// A running timer started on an earlier day.
    case staleTimer(TimeEntry)
    /// A workday with nothing logged.
    case emptyDay(LocalDate)
    /// A workday under the usual-day threshold the short-day nudge uses.
    case shortDay(LocalDate, logged: TimeInterval, usual: TimeInterval)
    /// Unlogged working time, on start-and-end accounts.
    case gap(TimeGap)
    /// An entry on a retired bucket.
    case retiredBucket(TimeEntry)
    /// An entry with no notes.
    case missingNotes(TimeEntry)

    public var day: LocalDate {
        switch self {
        case .staleTimer(let e), .retiredBucket(let e), .missingNotes(let e): e.spentDate
        case .emptyDay(let d), .shortDay(let d, _, _): d
        case .gap(let g): g.day
        }
    }

    public var id: String {
        switch self {
        case .staleTimer(let e): "timer-\(e.id)"
        case .emptyDay(let d): "empty-\(d)"
        case .shortDay(let d, _, _): "short-\(d)"
        case .gap(let g): "gap-\(g.id)"
        case .retiredBucket(let e): "retired-\(e.id)"
        case .missingNotes(let e): "notes-\(e.id)"
        }
    }

    /// Day-level items lead their day; then gaps, buckets, notes.
    var order: Int {
        switch self {
        case .staleTimer: 0
        case .emptyDay, .shortDay: 1
        case .gap: 2
        case .retiredBucket: 3
        case .missingNotes: 4
        }
    }
}

public enum WeekReview {
    /// On by default; Preferences → General turns the Friday reminder off.
    public static let enabledKey = "prefs.weekReview"
    /// Minutes after midnight, Central time.
    public static let reminderTimeKey = "prefs.weekReviewAt"
    public static let defaultReminderMinutes = 16 * 60
    /// Timesheets close Friday at 6:00 PM Central.
    public static let deadlineMinutes = 18 * 60
    /// Gaps you've said weren't work, by `TimeGap.id`.
    public static let ignoredGapsKey = "weekReview.ignoredGaps"
    /// The Central date the reminder last went out, "2026-11-13".
    public static let lastRemindedKey = "weekReview.lastReminded"
    public static let central = TimeZone(identifier: "America/Chicago")!

    static var centralCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = central
        return calendar
    }

    /// Monday–Friday of the week that holds `today`, through `today`.
    public static func workdays(today: LocalDate, firstWeekday: Int) -> [LocalDate] {
        let start = today.startOfWeek(firstWeekday: firstWeekday)
        return (0..<7).map { start.adding(days: $0) }.filter { $0 <= today && (2...6).contains($0.weekday) }
    }

    /// Everything to sort out this week, oldest day first.
    /// Earlier days count as short under the short-day threshold; today does
    /// too on Friday, the day the week closes. Gaps only come from accounts
    /// that track start and end times, and today's stop at `now`.
    public static func items(
        today: LocalDate, now: Date, firstWeekday: Int, usualDay: TimeInterval, entries: [TimeEntry],
        tracksStartAndEnd: Bool, workday: Range<Int> = GapFinder.defaultWorkday,
        ignoredGaps: Set<String> = [], calendar: Calendar = .current
    ) -> [ReviewItem] {
        var items: [ReviewItem] = []
        if let stale = entries.first(where: { $0.isRunning && $0.spentDate < today }) {
            items.append(.staleTimer(stale))
        }
        for day in workdays(today: today, firstWeekday: firstWeekday) {
            let dayEntries = entries.filter { $0.spentDate == day }
            let logged = dayEntries.reduce(0) { $0 + $1.elapsed(at: now) }
            let countsWhole = day < today || day.weekday == 6
            if dayEntries.isEmpty {
                if countsWhole { items.append(.emptyDay(day)) }
                continue
            }
            if countsWhole, usualDay > 0, logged < usualDay * ShortDays.threshold {
                items.append(.shortDay(day, logged: logged, usual: usualDay))
            }
            if tracksStartAndEnd {
                let parts = calendar.dateComponents([.hour, .minute], from: now)
                let until = day == today ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : nil
                items += GapFinder.gaps(day: day, entries: dayEntries, workday: workday, until: until, now: now)
                    .filter { !ignoredGaps.contains($0.id) }
                    .map(ReviewItem.gap)
            }
            for entry in dayEntries where entry.lock == nil {
                if RetiredBuckets.isRetired(entry) {
                    items.append(.retiredBucket(entry))
                } else if !entry.isRunning, (entry.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(.missingNotes(entry))
                }
            }
        }
        // A stale timer first; then by day, then kind, keeping each day's entry order.
        return items.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if (x.order == 0) != (y.order == 0) { return x.order == 0 }
            if x.day != y.day { return x.day < y.day }
            if x.order != y.order { return x.order < y.order }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Friday reminder

    /// The Central date to remind for, when it's Friday in Central time, at or
    /// after the reminder time and before the week closes, and today's
    /// reminder hasn't gone out yet. Nil otherwise.
    public static func reminderDue(now: Date, reminderMinutes: Int, lastReminded: String?) -> String? {
        let calendar = centralCalendar
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard parts.weekday == 6 else { return nil }
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard minutes >= reminderMinutes, minutes < max(deadlineMinutes, reminderMinutes + 60) else { return nil }
        let key = LocalDate(now, calendar: calendar).description
        return key == lastReminded ? nil : key
    }

    /// The moment `centralMinutes` falls on the Central date of `reference`,
    /// for showing a Central time in the Mac's own time zone.
    public static func date(centralMinutes: Int, on reference: Date = .now) -> Date {
        let calendar = centralCalendar
        let midnight = calendar.startOfDay(for: reference)
        return calendar.date(byAdding: .minute, value: centralMinutes, to: midnight) ?? reference
    }

    /// Minutes after midnight in Central time.
    public static func centralMinutes(of date: Date) -> Int {
        let parts = centralCalendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// This week's Friday 6:00 PM Central, as a moment (shown in local time).
    public static func deadline(containing today: LocalDate, firstWeekday: Int) -> Date {
        let start = today.startOfWeek(firstWeekday: firstWeekday)
        let friday = (0..<7).map { start.adding(days: $0) }.first { $0.weekday == 6 } ?? today
        let calendar = centralCalendar
        let midnight = calendar.date(from: DateComponents(year: friday.year, month: friday.month, day: friday.day)) ?? .now
        return calendar.date(byAdding: .minute, value: deadlineMinutes, to: midnight) ?? midnight
    }
}

extension TimeTracker {
    /// Whether this account writes start and end times on entries.
    public var tracksStartAndEndTimes: Bool { tracksStartAndEnd }

    /// This week's review as of `today` and `now`.
    public func weekReview(today: LocalDate = LocalDate(), now: Date = .now, defaults: UserDefaults = .standard) -> [ReviewItem] {
        WeekReview.items(
            today: today, now: now, firstWeekday: firstWeekday, usualDay: usualDaySeconds,
            entries: entries.filter { $0.spentDate >= today.startOfWeek(firstWeekday: firstWeekday) && $0.spentDate <= today },
            tracksStartAndEnd: tracksStartAndEnd, workday: GapFinder.workday(defaults),
            ignoredGaps: WeekReview.ignoredGaps(defaults)
        )
    }

    /// Unlogged working time on `day`, when it's today or an earlier workday
    /// this week, on an account that tracks start and end times.
    public func gaps(on day: LocalDate, today: LocalDate = LocalDate(), now: Date = .now, defaults: UserDefaults = .standard) -> [TimeGap] {
        guard tracksStartAndEnd, WeekReview.workdays(today: today, firstWeekday: firstWeekday).contains(day) else { return [] }
        let dayEntries = entries(on: day)
        guard !dayEntries.isEmpty else { return [] }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let until = day == today ? (parts.hour ?? 0) * 60 + (parts.minute ?? 0) : nil
        let ignored = WeekReview.ignoredGaps(defaults)
        return GapFinder.gaps(day: day, entries: dayEntries, workday: GapFinder.workday(defaults), until: until, now: now)
            .filter { !ignored.contains($0.id) }
    }
}

extension WeekReview {
    /// Stored comma-separated, so views can watch it with `@AppStorage`.
    public static func ignoredGaps(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.string(forKey: ignoredGapsKey) ?? "").split(separator: ",").map(String.init))
    }

    /// Marks a gap as not work (lunch, a break), so it stops coming up.
    /// Keeps the last 200.
    public static func ignore(_ gap: TimeGap, defaults: UserDefaults = .standard) {
        var list = (defaults.string(forKey: ignoredGapsKey) ?? "").split(separator: ",").map(String.init)
        guard !list.contains(gap.id) else { return }
        list.append(gap.id)
        defaults.set(list.suffix(200).joined(separator: ","), forKey: ignoredGapsKey)
    }
}
