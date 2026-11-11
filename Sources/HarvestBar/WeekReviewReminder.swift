import AppKit
import HarvestKit
import HarvestUI
import SwiftUI

/// Fridays at 4:00 PM Central (or the time set in Preferences), says the
/// week closes at 6 and opens the Week Review when clicked. Central time is
/// worked out with the Mac's own time zone data, so it's right wherever the
/// Mac is and across daylight saving.
@MainActor
final class WeekReviewReminder {
    /// Set in the notification's userInfo so a click opens the review.
    nonisolated static let openKey = "open"
    nonisolated static let openValue = "weekReview"

    private let tracker: TimeTracker
    private var timer: Timer?

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            WeekReview.enabledKey: true,
            WeekReview.reminderTimeKey: WeekReview.defaultReminderMinutes,
        ])
    }

    init(tracker: TimeTracker) {
        self.tracker = tracker
        Self.registerDefaults()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func check() {
        let defaults = UserDefaults.standard
        guard tracker.phase == .ready, defaults.bool(forKey: WeekReview.enabledKey),
              let key = WeekReview.reminderDue(now: .now, reminderMinutes: defaults.integer(forKey: WeekReview.reminderTimeKey),
                                               lastReminded: defaults.string(forKey: WeekReview.lastRemindedKey))
        else { return }
        defaults.set(key, forKey: WeekReview.lastRemindedKey)
        let count = tracker.weekReview().count
        Notifier.post(
            id: "week-review-\(key)", title: "Your week closes at 6 PM Central",
            body: count == 0 ? "Everything looks in. Take a quick look before it closes."
                : count == 1 ? "1 thing to sort out first. Click to review your week." : "\(count) things to sort out first. Click to review your week.",
            userInfo: [Self.openKey: Self.openValue]
        )
    }
}

/// Preferences → General → Reminders: the Friday review toggle and its time,
/// in Central, with what that is here.
struct WeekReviewPrefsRow: View {
    @AppStorage(WeekReview.enabledKey) private var isEnabled = true
    @AppStorage(WeekReview.reminderTimeKey) private var minutes = WeekReview.defaultReminderMinutes

    private var time: Binding<Date> {
        Binding(get: { WeekReview.date(centralMinutes: minutes) },
                set: { minutes = WeekReview.centralMinutes(of: $0) })
    }

    var body: some View {
        let local = WeekReview.date(centralMinutes: minutes)
        let sameZone = TimeZone.current.secondsFromGMT(for: local) == WeekReview.central.secondsFromGMT(for: local)
        SettingsRow("Review my week on Fridays",
                    description: "Timesheets close Friday at 6:00 PM Central. The Week Review shows short days, gaps, missing notes and retired buckets. It's also in the window's gear menu.",
                    icon: RowIcon("checklist", .teal), isOn: $isEnabled)
            .onChange(of: isEnabled) { _, on in if on { Notifier.requestPermission() } }
        CardDivider()
        SettingsRow("At", description: sameZone ? nil : "\(local.formatted(date: .omitted, time: .shortened)) here") {
            HStack(spacing: 6) {
                DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
                    .environment(\.timeZone, WeekReview.central)
                Text("Central").foregroundStyle(.secondary)
            }
        }
        .disabled(!isEnabled)
    }
}
