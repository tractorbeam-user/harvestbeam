import AppKit
import HarvestKit
import UserNotifications

/// Posts Harvestbeam's own macOS notifications. Clicking one shows the window.
@MainActor
enum Notifier {
    /// Notifications need a real app bundle; debug runs from `swift build` have none.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// An Autotracker match: "Start" (or clicking it) starts the task.
    static let autotrackCategory = "AUTOTRACK"
    static let startAction = "START"
    /// A meeting logged on its own: "Undo" deletes the entry.
    static let autoLoggedCategory = "AUTOLOGGED"
    static let undoAction = "UNDO"

    static func registerCategories() {
        center?.setNotificationCategories([
            UNNotificationCategory(identifier: autotrackCategory,
                                   actions: [UNNotificationAction(identifier: startAction, title: "Start")],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: autoLoggedCategory,
                                   actions: [UNNotificationAction(identifier: undoAction, title: "Undo", options: [.destructive])],
                                   intentIdentifiers: []),
        ])
    }

    static func post(id: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    static func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        center?.delegate = delegate
    }
}

/// Checks every half minute for reminders (nothing tracked by a set time, a
/// timer running too long) and for idle time while a timer runs.
@MainActor
final class Reminders {
    private let tracker: TimeTracker
    private let onReturnFromIdle: (_ idleSeconds: TimeInterval, _ entryID: Int) -> Void
    private var timer: Timer?
    private var idleSince: Date?
    /// The timer that was running when you went idle: only it gets asked about.
    private var idleEntryID: Int?
    private var sleepObserver: NSObjectProtocol?
    private var remindedNoTimerOn: LocalDate?
    private var remindedLongTimerFor: Int?

    init(tracker: TimeTracker, onReturnFromIdle: @escaping (TimeInterval, Int) -> Void) {
        self.tracker = tracker
        self.onReturnFromIdle = onReturnFromIdle
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // .common: keeps checking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Closing the lid is going away too, though no idle time builds up
        // while asleep: note when it went, and ask once you're back.
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteIdleStart(at: Date()) }
        }
    }

    private func noteIdleStart(at date: Date) {
        guard UserDefaults.standard.bool(forKey: Prefs.idleDetection), let entry = tracker.running, idleSince == nil else { return }
        // Not before this timer started: away time from before it isn't its.
        idleSince = max(date, entry.timerStartedAt ?? date)
        idleEntryID = entry.id
    }

    private func check() {
        guard tracker.phase == .ready else { return }
        let defaults = UserDefaults.standard
        checkIdle(defaults)

        let now = Date()
        let today = LocalDate(now)

        // Nothing tracked by the reminder time on a weekday.
        if defaults.bool(forKey: Prefs.remindNoTimer), remindedNoTimerOn != today,
           (2...6).contains(today.weekday), tracker.running == nil, tracker.entries(on: today).isEmpty {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if minutes >= defaults.integer(forKey: Prefs.remindNoTimerAt) {
                remindedNoTimerOn = today
                Notifier.post(id: "no-timer-\(today)", title: "Nothing tracked yet today",
                              body: "Start a timer or plan your day in Harvestbeam.")
            }
        }

        // A timer running longer than the set number of hours.
        if defaults.bool(forKey: Prefs.remindLongTimer), let entry = tracker.running, remindedLongTimerFor != entry.id {
            let limit = Double(defaults.integer(forKey: Prefs.remindLongTimerHours)) * 3600
            if entry.elapsed(at: now) >= limit {
                remindedLongTimerFor = entry.id
                let task = tracker.task(for: entry)
                Notifier.post(id: "long-timer-\(entry.id)", title: "Timer still running",
                              body: "\(task.project.name) · \(task.task.name) has been running for \(TimeFormat.hoursMinutes(entry.elapsed(at: now))).")
            }
        }
    }

    /// Notes when you went idle with a timer running, and asks about it once
    /// you're back.
    private func checkIdle(_ defaults: UserDefaults) {
        // Paused or switched since: that was you, back already.
        guard defaults.bool(forKey: Prefs.idleDetection), let running = tracker.running,
              idleEntryID == nil || idleEntryID == running.id else {
            idleSince = nil
            idleEntryID = nil
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let threshold = Double(max(1, defaults.integer(forKey: Prefs.idleMinutes))) * 60
        if idle >= threshold {
            noteIdleStart(at: Date().addingTimeInterval(-idle))
        } else if let since = idleSince, let entryID = idleEntryID, idle < 30 {
            idleSince = nil
            idleEntryID = nil
            let away = Date().timeIntervalSince(since) - idle
            if away >= threshold { onReturnFromIdle(away, entryID) }
        }
    }
}
