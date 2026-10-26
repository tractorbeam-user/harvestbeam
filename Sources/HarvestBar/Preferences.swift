import AppKit
import Carbon.HIToolbox
import HarvestKit
import HarvestUI
import ServiceManagement
import SwiftUI

/// Preferences keys and defaults, shared by the window and the app delegate.
enum Prefs {
    static let showInDock = "prefs.showInDock"
    static let idleDetection = "prefs.idleDetection"
    static let idleMinutes = "prefs.idleMinutes"
    static let remindNoTimer = "prefs.remindNoTimer"
    /// Minutes after midnight.
    static let remindNoTimerAt = "prefs.remindNoTimerAt"
    static let remindLongTimer = "prefs.remindLongTimer"
    static let remindLongTimerHours = "prefs.remindLongTimerHours"
    static let shortcutDisplay = "shortcut.toggle.display"
    static let continueShortcutDisplay = "shortcut.continue.display"

    static func register() {
        UserDefaults.standard.register(defaults: [
            showInDock: false,
            idleDetection: true,
            idleMinutes: 10,
            remindNoTimer: false,
            remindNoTimerAt: 10 * 60,
            remindLongTimer: false,
            remindLongTimerHours: 4,
            shortcutDisplay: "⌥H",
        ])
    }

    static func applyDockVisibility() {
        NSApp.setActivationPolicy(UserDefaults.standard.bool(forKey: showInDock) ? .regular : .accessory)
    }
}

extension Notification.Name {
    /// Posted when the show/hide shortcut changes in Preferences.
    static let toggleShortcutChanged = Notification.Name("HarvestBar.toggleShortcutChanged")
}

/// A native Preferences window with General, Shortcuts and Support tabs in
/// the toolbar, like Harvest's own.
@MainActor
final class PreferencesWindowController: NSWindowController {
    init(tracker: TimeTracker, updates: Updates, recorder: ActivityRecorder?, resetLayout: @escaping () -> Void) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = false
        func tab(_ label: String, _ symbol: String, _ view: some View) -> NSTabViewItem {
            let host = NSHostingController(rootView: view.environment(tracker).environment(updates).environment(recorder).tint(.harvestOrange))
            host.sizingOptions = [.preferredContentSize]
            let item = NSTabViewItem(viewController: host)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            return item
        }
        tabs.addTabViewItem(tab("General", "gearshape", GeneralPrefs()))
        if recorder != nil { tabs.addTabViewItem(tab("Tracking", "wand.and.stars", TrackingPrefs())) }
        tabs.addTabViewItem(tab("Shortcuts", "command", ShortcutPrefs()))
        tabs.addTabViewItem(tab("Support", "wrench.adjustable", SupportPrefs(resetLayout: resetLayout)))

        let window = NSWindow(contentViewController: tabs)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: General

struct GeneralPrefs: View {
    @Environment(Updates.self) private var updates
    @AppStorage(Prefs.showInDock) private var showInDock = false
    @AppStorage(Prefs.idleDetection) private var idleDetection = true
    @AppStorage(Prefs.idleMinutes) private var idleMinutes = 10
    @AppStorage(Prefs.remindNoTimer) private var remindNoTimer = false
    @AppStorage(Prefs.remindNoTimerAt) private var remindNoTimerAt = 600
    @AppStorage(Prefs.remindLongTimer) private var remindLongTimer = false
    @AppStorage(Prefs.remindLongTimerHours) private var remindLongTimerHours = 4
    @AppStorage(ShortDays.enabledKey) private var nudgesShortDays = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        PrefsPage {
            PrefsSection("Behavior") {
                Toggle("Open Harvestbeam at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                Toggle("Show in Dock and app switcher", isOn: $showInDock)
                    .onChange(of: showInDock) { Prefs.applyDockVisibility() }
                HStack(spacing: 6) {
                    Toggle("Detect idle time after", isOn: $idleDetection)
                    TextField("", value: $idleMinutes, format: .number)
                        .frame(width: 40)
                        .multilineTextAlignment(.center)
                        .disabled(!idleDetection)
                    Text("minutes of inactivity")
                }
                Text("When you come back to a running timer, Harvestbeam asks whether to keep the time you were away.")
                    .prefsNote()
            }
            Divider()
            PrefsSection("Reminders") {
                HStack(spacing: 6) {
                    Toggle("Remind me if nothing's tracked by", isOn: $remindNoTimer)
                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .disabled(!remindNoTimer)
                    Text("on weekdays")
                }
                HStack(spacing: 6) {
                    Toggle("Tell me when a timer has run for", isOn: $remindLongTimer)
                    Stepper(value: $remindLongTimerHours, in: 1...12) {
                        Text("\(remindLongTimerHours) h").monospacedDigit()
                    }
                    .disabled(!remindLongTimer)
                }
                Text("Reminders are macOS notifications from Harvestbeam itself; click one to open the window. Turning one on asks for permission once.")
                    .prefsNote()
                Toggle("Point out short days earlier in the week", isOn: $nudgesShortDays)
                Text("A day under three quarters of your usual day (your Harvest weekly capacity ÷ 5) gets a dot in the week strip and a note above your entries.")
                    .prefsNote()
            }
            .onChange(of: remindNoTimer) { _, on in if on { Notifier.requestPermission() } }
            .onChange(of: remindLongTimer) { _, on in if on { Notifier.requestPermission() } }
            Divider()
            PrefsSection("Updates") {
                @Bindable var updates = updates
                HStack {
                    Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
                    Spacer()
                    Button("Check Now") { updates.checkForUpdates(nil) }
                        .disabled(!updates.canCheck)
                }
                Toggle("Install updates automatically", isOn: $updates.installsAutomatically)
                    .disabled(!updates.checksAutomatically)
                Text("Harvestbeam looks for a new version on GitHub once a day. Unless it installs them automatically, it asks first."
                     + (Beta.isEnabled ? " You're on the beta, so you get beta versions as well as regular ones. To leave it, install the regular version from the website." : ""))
                    .prefsNote()
            }
        }
    }

    /// The reminder time as a Date for the picker, stored as minutes after midnight.
    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: remindNoTimerAt / 60, minute: remindNoTimerAt % 60, second: 0, of: .now) ?? .now },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                remindNoTimerAt = (parts.hour ?? 10) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

// MARK: Shortcuts

struct ShortcutPrefs: View {
    @AppStorage(Prefs.shortcutDisplay) private var display = "⌥H"
    @AppStorage(Prefs.continueShortcutDisplay) private var continueDisplay = ""

    private let inApp: [(String, String)] = [
        ("New time entry", "⌘N"), ("Plan your day", "⌘P"), ("Search tasks", "⌘F"),
        ("Go to today", "⌘T"), ("Previous / next day", "⌘[  ⌘]"), ("Pause the timer", "⌘."),
        ("Undo delete", "⌘Z"), ("Refresh", "⌘R"), ("Reset window size", "⌘0"),
    ]

    var body: some View {
        PrefsPage {
            PrefsSection("Anywhere on your Mac") {
                ShortcutRecorder(title: "Show or hide Harvestbeam", name: "toggle", display: $display)
                if Beta.isEnabled {
                    ShortcutRecorder(title: "Continue last entry, or stop the timer", name: "continue", display: $continueDisplay)
                }
                Text("Use ⌘, ⌥ or ⌃ with a key. Esc cancels."
                     + (Beta.isEnabled ? " Continue picks up your most recent entry; if a timer's running, it stops it." : "")).prefsNote()
            }
            Divider()
            PrefsSection("In the Harvestbeam window") {
                ForEach(inApp, id: \.0) { name, keys in
                    HStack {
                        Text(name)
                        Spacer()
                        Text(keys).font(.body.monospaced()).foregroundStyle(Color.secondary)
                    }
                }
            }
            Divider()
            Button("Restore Default Shortcuts") {
                HotKey.Shortcut.save(.default)
                display = "⌥H"
                HotKey.Shortcut.save(nil, as: "continue")
                continueDisplay = ""
                NotificationCenter.default.post(name: .toggleShortcutChanged, object: nil)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// One global shortcut: click, then type the keys.
private struct ShortcutRecorder: View {
    let title: String
    /// "toggle" or "continue", as `HotKey.Shortcut` stores it.
    let name: String
    @Binding var display: String
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button { recording ? stopRecording() : startRecording() } label: {
                Text(recording ? "Type a shortcut…" : (display.isEmpty ? "None" : display))
                    .foregroundStyle(recording ? Color.harvestOrange : (display.isEmpty ? Color.secondary : Color.primary))
                    .frame(width: 150)
            }
            if !display.isEmpty {
                Button { save(nil, display: "") } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Remove this shortcut")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stopRecording(); return nil }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            var carbon = 0
            var symbols = ""
            if flags.contains(.control) { carbon |= controlKey; symbols += "⌃" }
            if flags.contains(.option) { carbon |= optionKey; symbols += "⌥" }
            if flags.contains(.shift) { carbon |= shiftKey; symbols += "⇧" }
            if flags.contains(.command) { carbon |= cmdKey; symbols += "⌘" }
            let key = (event.charactersIgnoringModifiers ?? "").uppercased()
            save(HotKey.Shortcut(keyCode: Int(event.keyCode), carbonModifiers: carbon), display: symbols + key)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func save(_ shortcut: HotKey.Shortcut?, display: String) {
        HotKey.Shortcut.save(shortcut, as: name)
        self.display = display
        NotificationCenter.default.post(name: .toggleShortcutChanged, object: nil)
    }
}

// MARK: Tracking

/// Toggl-style automatic tracking: the Timeline, on-screen suggestions,
/// Autotracker rules and auto-logged meetings. All off until turned on.
struct TrackingPrefs: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(ActivityRecorder.self) private var recorder
    @AppStorage(ActivityRecorder.timelineKey) private var records = false
    @AppStorage(ActivityRecorder.websitesKey) private var websites = true
    @AppStorage(ActivityRecorder.excludedKey) private var excluded = ActivityRecorder.defaultExcluded
    @AppStorage(ActivityRecorder.suggestionsKey) private var suggests = false
    @AppStorage(ActivityRecorder.autotrackKey) private var autotracks = false
    @AppStorage(ActivityRecorder.autotrackStartKey) private var startsAutomatically = false
    @AppStorage(ActivityRecorder.autotrackStopKey) private var stopsWhenUnmatched = false
    @AppStorage(ActivityRecorder.autotrackDelayKey) private var delay = 5
    @AppStorage(ActivityRecorder.autoLogMeetingsKey) private var logsMeetings = false
    @State private var hasAccessibility = ActivityRecorder.hasAccessibility
    @State private var isAddingRule = false
    @State private var confirmsDelete = false

    var body: some View {
        PrefsPage {
            if (records || suggests || autotracks) && !hasAccessibility {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Window titles need Accessibility access").font(.headline)
                        Text("Without it, only app names are seen, so rules and suggestions can't tell one document or site from another.").prefsNote()
                    }
                    Spacer()
                    Button("Allow…") { ActivityRecorder.requestAccessibility() }
                }
                Divider()
            }
            PrefsSection("Timeline") {
                Toggle("Record my Timeline", isOn: $records)
                Toggle("Include the website in browsers (just the domain)", isOn: $websites)
                    .disabled(!records && !suggests && !autotracks)
                HStack {
                    Text("Never record")
                    TextField("App names, separated by commas", text: $excluded)
                }
                Text("Notes each app and window you spend more than 10 seconds in, so the Week Calendar can show what you worked on and what wasn't tracked. It stays on this Mac for two weeks; nothing goes to Harvest unless you log it.")
                    .prefsNote()
                Button("Delete Timeline…") { confirmsDelete = true }
                    .confirmationDialog("Delete everything the Timeline has recorded?", isPresented: $confirmsDelete) {
                        Button("Delete Timeline", role: .destructive) { recorder.deleteTimeline() }
                    }
            }
            Divider()
            PrefsSection("Suggestions") {
                Toggle("Suggest tasks from what's on screen", isOn: $suggests)
                Text("The ask box's first suggestion becomes the task that the app and window you were just in point to: your rules, where you've tracked before, and project or client names in the title.")
                    .prefsNote()
            }
            Divider()
            PrefsSection("Autotracker") {
                Toggle("Track with rules", isOn: $autotracks)
                    .onChange(of: autotracks) { _, on in if on { Notifier.requestPermission() } }
                RulesList(isAdding: $isAddingRule)
                    .disabled(!autotracks)
                Picker("When a rule matches", selection: $startsAutomatically) {
                    Text("Ask first").tag(false)
                    Text("Start the timer").tag(true)
                }
                .disabled(!autotracks)
                Stepper(value: $delay, in: 1...300) {
                    Text("After \(delay) seconds in the window").monospacedDigit()
                }
                .disabled(!autotracks)
                Toggle("Stop the timer when no rule matches any more", isOn: $stopsWhenUnmatched)
                    .disabled(!autotracks)
                Text("A rule matches when the app's name, the window title or the website contains any of its keywords. It never takes over a timer you started yourself without asking, and only stops timers it started.")
                    .prefsNote()
            }
            Divider()
            PrefsSection("Calendar") {
                Toggle("Log meetings automatically", isOn: $logsMeetings)
                    .onChange(of: logsMeetings) { _, on in if on { Notifier.requestPermission() } }
                Text("Within five minutes of a meeting starting, it's logged to its matched task, and a notification lets you undo. Meetings with no match, no length, or added after they started are left for you.")
                    .prefsNote()
            }
        }
        .sheet(isPresented: $isAddingRule) { AddRuleSheet().environment(tracker) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = ActivityRecorder.hasAccessibility
        }
        .onAppear { hasAccessibility = ActivityRecorder.hasAccessibility }
    }
}

/// Your Autotracker rules, top one first.
private struct RulesList: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var isAdding: Bool

    var body: some View {
        let rules = tracker.contextMemory.rules
        VStack(alignment: .leading, spacing: 0) {
            if rules.isEmpty {
                Text("No rules yet").foregroundStyle(Color.secondary).padding(8)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        let task = tracker.tasks(for: [rule.taskKey]).first
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.keywords).fontWeight(.medium)
                                Text(task.map { "→ \($0.projectNameParts.name) · \($0.task.name)" } ?? "→ a task you're no longer assigned to")
                                    .font(.callout).foregroundStyle(Color.secondary)
                            }
                            Spacer()
                            Button { tracker.contextMemory.setRules(rules.filter { $0.id != rule.id }) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this rule")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                }
            }
            .frame(maxHeight: 150)
            Divider()
            Button("Add Rule…") { isAdding = true }
                .buttonStyle(.borderless)
                .padding(8)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Keywords, then the task they mean.
private struct AddRuleSheet: View {
    @Environment(TimeTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss
    @State private var keywords = ""
    @State private var query = ""
    @State private var picked: TaskKey?

    var body: some View {
        let results = query.isEmpty ? tracker.recentTasks + tracker.favoriteTasks : Array(tracker.search(query).prefix(30))
        VStack(alignment: .leading, spacing: 12) {
            Text("New Autotracker Rule").font(.headline)
            TextField("Keywords, e.g. Figma, Pinstripes", text: $keywords)
            Text("Matches when the app's name, window title or website contains any of them.").prefsNote()
            TextField("Search for the task", text: $query)
            List(results, selection: $picked) { task in
                VStack(alignment: .leading, spacing: 1) {
                    Text(task.projectNameParts.name).fontWeight(.medium)
                    Text("\(task.task.name) · \(task.client?.name ?? "")").font(.callout).foregroundStyle(Color.secondary)
                }
                .tag(task.key)
            }
            .frame(height: 200)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Rule") {
                    guard let picked else { return }
                    tracker.contextMemory.setRules(tracker.contextMemory.rules + [AutotrackRule(keywords: keywords, taskKey: picked)])
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(picked == nil || keywords.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: Support

struct SupportPrefs: View {
    @Environment(TimeTracker.self) private var tracker
    let resetLayout: () -> Void
    @State private var reloaded = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        PrefsPage {
            PrefsSection("Reset App") {
                Text("Harvestbeam keeps your projects and recent entries in memory. Reload them from Harvest if something looks out of date.")
                    .prefsNote()
                Button(reloaded ? "Reloaded" : "Reload from Harvest") {
                    Task {
                        await tracker.refresh(force: true)
                        reloaded = true
                    }
                }
                .frame(maxWidth: .infinity)
                Text("Put the window size, folded sections and removed suggestions back the way they started.")
                    .prefsNote()
                Button("Reset Layout") {
                    tracker.showHiddenSuggestions()
                    UserDefaults.standard.removeObject(forKey: "collapsedSections")
                    resetLayout()
                }
                .frame(maxWidth: .infinity)
            }
            Divider()
            PrefsSection("Account") {
                HStack {
                    Text("Signed in to \(tracker.accountName ?? "Harvest")")
                    Spacer()
                    Button("Sign Out") { tracker.signOut() }
                }
            }
            Divider()
            PrefsSection("About") {
                HStack {
                    Text("Harvestbeam \(version)")
                    Spacer()
                    Link("Report a Problem…", destination: URL(string: "https://github.com/tractorbeam-user/harvestbeam/issues")!)
                }
                Text("An unofficial client for the Harvest API.").prefsNote()
            }
        }
    }
}

// MARK: Layout helpers

private struct PrefsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(24)
            .frame(width: 480, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PrefsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
    }
}

private extension View {
    func prefsNote() -> some View {
        font(.callout).foregroundStyle(Color.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
