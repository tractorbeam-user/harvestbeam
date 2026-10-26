import Foundation
import HarvestKit
import HarvestUI

/// Toggl's Autotracker: when the app or window in front matches one of your
/// rules for a few seconds, offer to start that task (or start it outright,
/// if you've said so). It never takes over a timer you started yourself
/// without asking, and can stop the timers it started once nothing matches.
@MainActor
final class Autotracker {
    private let tracker: TimeTracker
    /// The task whose timer the Autotracker started, while it's running.
    private var startedKey: TaskKey?
    /// When each rule last asked, so it asks once per stay, not every tick.
    private var askedAt: [UUID: Date] = [:]
    private var unmatchedSince: Date?

    init(tracker: TimeTracker) {
        self.tracker = tracker
    }

    func tick(_ context: ScreenContext?, dwell: TimeInterval) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ActivityRecorder.autotrackKey), tracker.phase == .ready else { return }
        let delay = TimeInterval(max(1, defaults.integer(forKey: ActivityRecorder.autotrackDelayKey)))
        if let key = startedKey, tracker.running?.key != key { startedKey = nil }
        // In Harvestbeam itself, or away: leave things as they are.
        guard let context else { return }

        guard let (rule, keyword) = tracker.contextMemory.rule(for: context),
              let task = tracker.tasks(for: [rule.taskKey]).first else {
            stopIfNothingMatches(after: delay)
            return
        }
        unmatchedSince = nil
        guard dwell >= delay, tracker.running?.key != task.key, tracker.busyKey == nil else { return }
        let yoursIsRunning = tracker.running != nil && startedKey == nil
        if defaults.bool(forKey: ActivityRecorder.autotrackStartKey) && !yoursIsRunning {
            start(task.key)
        } else {
            // Ask again only after you've been somewhere else for a while.
            if let asked = askedAt[rule.id], Date().timeIntervalSince(asked) < 15 * 60 { return }
            askedAt[rule.id] = .now
            let switching = tracker.running.map { tracker.task(for: $0).project.name }
            Notifier.post(
                id: "autotrack-\(rule.id)",
                title: switching == nil ? "Start \(task.projectNameParts.name)?" : "Switch to \(task.projectNameParts.name)?",
                body: "\(task.task.name) · your rule for “\(keyword)” matches \(context.app)."
                    + (switching.map { " \($0) is running." } ?? ""),
                category: Notifier.autotrackCategory,
                userInfo: ["task": task.key.description]
            )
        }
    }

    /// From the notification's Start button, or a click on it.
    func start(_ key: TaskKey) {
        guard let task = tracker.tasks(for: [key]).first, tracker.running?.key != key else { return }
        startedKey = key
        Task { await tracker.toggle(task) }
    }

    private func stopIfNothingMatches(after delay: TimeInterval) {
        guard UserDefaults.standard.bool(forKey: ActivityRecorder.autotrackStopKey),
              let key = startedKey, tracker.running?.key == key else {
            unmatchedSince = nil
            return
        }
        let since = unmatchedSince ?? .now
        unmatchedSince = since
        if Date().timeIntervalSince(since) >= delay {
            unmatchedSince = nil
            startedKey = nil
            Task { await tracker.pause() }
        }
    }
}

/// Toggl's auto-tracked calendar events: within five minutes of a meeting
/// starting, log it to its matched task. Like Toggl, it skips meetings added
/// after they started and ones with no length; unlike Toggl it also skips
/// meetings with no task match, since every Harvest entry needs a task.
@MainActor
final class MeetingAutoLogger {
    private let tracker: TimeTracker
    private let calendar: CalendarStore
    private var timer: Timer?
    /// Meetings already looked at, so each is only ever logged once.
    private var handled: Set<String> = []

    init(tracker: TimeTracker, calendar: CalendarStore) {
        self.tracker = tracker
        self.calendar = calendar
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        guard UserDefaults.standard.bool(forKey: ActivityRecorder.autoLogMeetingsKey),
              calendar.access == .granted, tracker.phase == .ready else { return }
        let now = Date()
        let today = LocalDate(now)
        for meeting in calendar.meetings(from: today, through: today) where !handled.contains(meeting.id) {
            let sinceStart = now.timeIntervalSince(meeting.start)
            guard sinceStart >= 0 else { continue }
            handled.insert(meeting.id)
            guard sinceStart <= 5 * 60, meeting.end > meeting.start else { continue }
            if let created = meeting.createdAt, created > meeting.start { continue }
            let suggestion: MeetingSuggestion
            switch tracker.status(of: meeting, at: now) {
            case .upcoming(let match?), .matched(let match): suggestion = match
            default: continue
            }
            Task {
                await tracker.log(meeting, task: suggestion.task, notes: meeting.title, hours: meeting.hours,
                                  remember: suggestion.reason == .remembered)
                guard let entry = tracker.entry(for: meeting) else { return }
                Notifier.post(
                    id: "autolog-\(meeting.id)",
                    title: "Logged \(meeting.title)",
                    body: "\(TimeFormat.hoursMinutes(meeting.hours * 3600)) to \(suggestion.task.projectNameParts.name) · \(suggestion.task.task.name)",
                    category: Notifier.autoLoggedCategory,
                    userInfo: ["entry": String(entry.id)]
                )
            }
        }
    }
}
