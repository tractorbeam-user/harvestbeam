import AppKit
import HarvestKit
import UserNotifications

/// Posts Harvest Bar's own macOS notifications. Clicking one shows the window.
@MainActor
enum Notifier {
    /// Notifications need a real app bundle; debug runs from `swift build` have none.
    private static var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    static func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
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
    private let onReturnFromIdle: (_ idleSeconds: TimeInterval) -> Void
    private var timer: Timer?
    private var idleSince: Date?
    private var remindedNoTimerOn: LocalDate?
    private var remindedLongTimerFor: Int?

    init(tracker: TimeTracker, onReturnFromIdle: @escaping (TimeInterval) -> Void) {
        self.tracker = tracker
        self.onReturnFromIdle = onReturnFromIdle
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
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
                              body: "Start a timer or plan your day in Harvest Bar.")
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
        guard defaults.bool(forKey: Prefs.idleDetection), tracker.running != nil else {
            idleSince = nil
            return
        }
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let threshold = Double(max(1, defaults.integer(forKey: Prefs.idleMinutes))) * 60
        if idle >= threshold {
            if idleSince == nil { idleSince = Date().addingTimeInterval(-idle) }
        } else if let since = idleSince, idle < 30 {
            idleSince = nil
            let away = Date().timeIntervalSince(since) - idle
            if away >= threshold { onReturnFromIdle(away) }
        }
    }
}
