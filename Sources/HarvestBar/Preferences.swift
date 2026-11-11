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
            showInDock: true,
            idleDetection: true,
            idleMinutes: 10,
            remindNoTimer: false,
            remindNoTimerAt: 10 * 60,
            remindLongTimer: false,
            remindLongTimerHours: 4,
            shortcutDisplay: "⌥H",
            Analytics.enabledKey: true,
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

/// The Preferences window: a full-height sidebar of panes with the traffic
/// lights over it, and the chosen pane's grouped settings on the right.
@MainActor
final class PreferencesWindowController: NSWindowController {
    static let size = NSSize(width: 780, height: 600)

    init(tracker: TimeTracker, updates: Updates, recorder: ActivityRecorder?,
         showTour: @escaping () -> Void, resetLayout: @escaping () -> Void) {
        let root = PrefsRoot(panes: PrefsPane.allCases.filter { $0 != .tracking || recorder != nil },
                             resetLayout: resetLayout, showTour: showTour)
            .environment(tracker).environment(updates).environment(recorder)
        super.init(window: Self.makeWindow(root))
    }

    required init?(coder: NSCoder) { nil }

    /// A window with a transparent title bar and full-size content, so the
    /// sidebar runs to the top. Also used by the debug snapshots.
    static func makeWindow(_ root: some View, size: NSSize = size) -> NSWindow {
        let host = NSHostingController(rootView: root.frame(minWidth: size.width, minHeight: 420))
        host.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        // An empty toolbar makes the title bar as tall as the pane header,
        // so the traffic lights line up with the back and forward buttons.
        window.toolbar = NSToolbar(identifier: "Preferences")
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        return window
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Every pane, in the sidebar window.
struct PrefsRoot: View {
    let panes: [PrefsPane]
    var initial: PrefsPane = .general
    let resetLayout: () -> Void
    var showTour: () -> Void = {}

    var body: some View {
        SettingsWindow(panes: panes, initial: initial) { pane in
            switch pane {
            case .general: GeneralPrefs()
            case .tracking: TrackingPrefs()
            case .shortcuts: ShortcutPrefs()
            case .support: SupportPrefs(resetLayout: resetLayout, showTour: showTour)
            }
        }
    }
}

// MARK: General

struct GeneralPrefs: View {
    @Environment(Updates.self) private var updates
    @AppStorage(Prefs.showInDock) private var showInDock = true
    @AppStorage(Prefs.idleDetection) private var idleDetection = true
    @AppStorage(Prefs.idleMinutes) private var idleMinutes = 10
    @AppStorage(Prefs.remindNoTimer) private var remindNoTimer = false
    @AppStorage(Prefs.remindNoTimerAt) private var remindNoTimerAt = 600
    @AppStorage(Prefs.remindLongTimer) private var remindLongTimer = false
    @AppStorage(Prefs.remindLongTimerHours) private var remindLongTimerHours = 4
    @AppStorage(ShortDays.enabledKey) private var nudgesShortDays = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage(Analytics.enabledKey) private var sharesUsage = true
    @Environment(TimeTracker.self) private var tracker

    var body: some View {
        PrefsPage {
            SettingsSection("Behavior") {
                SettingsRow("Open \(AppInfo.name) at login", icon: RowIcon("power", .green), isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
                CardDivider()
                SettingsRow("Show in Dock and app switcher", icon: RowIcon("dock.rectangle", .blue), isOn: $showInDock)
                    .onChange(of: showInDock) { Prefs.applyDockVisibility() }
            }
            SettingsSection("Idle Time") {
                SettingsRow("Detect idle time",
                            description: "When you come back to a running timer, \(AppInfo.name) asks whether to keep the time you were away.",
                            icon: RowIcon("moon.zzz.fill", .indigo), isOn: $idleDetection)
                CardDivider()
                SettingsRow("Idle after") {
                    SettingsPopup(selection: $idleMinutes, choices: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]) {
                        "\($0) \($0 == 1 ? "minute" : "minutes") of inactivity"
                    }
                }
                .disabled(!idleDetection)
            }
            SettingsSection("Reminders",
                            footer: "Reminders are macOS notifications from \(AppInfo.name) itself; click one to open the window. Turning one on asks for permission once.") {
                SettingsRow("Remind me if nothing's tracked", description: "On weekdays",
                            icon: RowIcon("bell.badge.fill", .red), isOn: $remindNoTimer)
                CardDivider()
                SettingsRow("By") {
                    DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .fixedSize()
                }
                .disabled(!remindNoTimer)
                CardDivider()
                SettingsRow("Tell me when a timer runs long", icon: RowIcon("timer", .orange), isOn: $remindLongTimer)
                CardDivider()
                SettingsRow("After running for") {
                    SettingsPopup(selection: $remindLongTimerHours, options: Array(1...12)) { "\($0) \($0 == 1 ? "hour" : "hours")" }
                }
                .disabled(!remindLongTimer)
                CardDivider()
                SettingsRow("Point out short days earlier in the week",
                            description: "A day under three quarters of your usual day (your Harvest weekly capacity ÷ 5) gets a dot in the week strip and a note above your entries.",
                            icon: RowIcon("calendar.badge.exclamationmark", .pink), isOn: $nudgesShortDays)
            }
            .onChange(of: remindNoTimer) { _, on in if on { Notifier.requestPermission() } }
            .onChange(of: remindLongTimer) { _, on in if on { Notifier.requestPermission() } }
            UpdatesSection()
            if Analytics.isAvailable {
                SettingsSection("Privacy") {
                    SettingsRow("Share anonymous usage stats",
                                description: "Helps show how many people use \(AppInfo.name) and which versions they're on: a random ID, the app and macOS version, and when you sign in or start a timer. Nothing from Harvest, like your projects, clients, notes or times, ever leaves your Mac.",
                                icon: RowIcon("hand.raised.fill", .gray), isOn: $sharesUsage)
                        .onChange(of: sharesUsage) { Analytics.update(isDemo: tracker.isDemo) }
                }
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

private struct UpdatesSection: View {
    @Environment(Updates.self) private var updates

    var body: some View {
        @Bindable var updates = updates
        SettingsSection("Updates",
                        footer: "\(AppInfo.name) looks for a new version on GitHub once a day. Unless it installs them automatically, it asks first."
                            + (Beta.isEnabled ? " This is the beta, a separate app from Harvestbeam, so it gets new betas. To leave it, quit it and move it to the Trash." : "")) {
            SettingsRow("Check for updates automatically", icon: RowIcon("arrow.triangle.2.circlepath", .teal),
                        isOn: $updates.checksAutomatically)
            CardDivider()
            SettingsRow("Install updates automatically", icon: RowIcon("arrow.down.circle.fill", .blue),
                        isOn: $updates.installsAutomatically)
                .disabled(!updates.checksAutomatically)
            CardDivider()
            SettingsRow("Look for a new version now") {
                Button("Check Now") { updates.checkForUpdates(nil) }
                    .disabled(!updates.canCheck)
            }
        }
    }
}

// MARK: Shortcuts

struct ShortcutPrefs: View {
    @AppStorage(Prefs.shortcutDisplay) private var display = "⌥H"
    @AppStorage(Prefs.continueShortcutDisplay) private var continueDisplay = ""

    private let inApp: [(String, String)] = [
        ("New time entry", "⌘N"), ("Plan your day", "⌘P"), ("Search tasks", "⌘F"),
        ("Go to today", "⌘T"), ("Previous / next day", "⌘[ ⌘]"), ("Pause the timer", "⌘."),
        ("Undo delete", "⌘Z"), ("Refresh", "⌘R"), ("Reset window size", "⌘0"),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            PrefsPage {
                SettingsSection("Anywhere on your Mac") {
                    ShortcutRecorder(title: "Show or hide \(AppInfo.name)", name: "toggle", display: $display)
                    if Beta.isEnabled {
                        CardDivider()
                        ShortcutRecorder(title: "Continue last entry, or stop the timer", name: "continue", display: $continueDisplay)
                    }
                }
                SettingsSection("In the \(AppInfo.name) window") {
                    ForEach(Array(inApp.enumerated()), id: \.offset) { index, item in
                        if index > 0 { CardDivider() }
                        SettingsRow(item.0) { Keycaps(combo: item.1) }
                    }
                }
                Button("Restore Default Shortcuts") {
                    HotKey.Shortcut.save(.default)
                    display = "⌥H"
                    HotKey.Shortcut.save(nil, as: "continue")
                    continueDisplay = ""
                    NotificationCenter.default.post(name: .toggleShortcutChanged, object: nil)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Click a shortcut, then type the new keys. Use ⌘, ⌥ or ⌃ with a key. Esc cancels.")
                if Beta.isEnabled {
                    Text("Continue picks up your most recent entry; if a timer's running, it stops it.")
                }
                Text("Shortcuts in the window work while \(AppInfo.name) is in front.")
            }
            .settingsNote()
            .frame(width: 150, alignment: .leading)
            .padding(.top, 30)
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
        SettingsRow(title) {
            HStack(spacing: 6) {
                Button { recording ? stopRecording() : startRecording() } label: {
                    Group {
                        if recording {
                            Text("Type a shortcut…").foregroundStyle(Color.harvestOrange)
                        } else if display.isEmpty {
                            Text("None").foregroundStyle(Color.secondary)
                        } else {
                            Keycaps(combo: display)
                        }
                    }
                    .frame(minWidth: 110, minHeight: 26)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(SettingsStyle.content))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recording ? Color.harvestOrange : SettingsStyle.hairline, lineWidth: recording ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click, then type a new shortcut")
                if !display.isEmpty {
                    Button { save(nil, display: "") } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this shortcut")
                } else {
                    Color.clear.frame(width: 14, height: 1)
                }
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
                SettingsCard {
                    SettingsRow("Window titles need Accessibility access",
                                description: "Without it, only app names are seen, so rules and suggestions can't tell one document or site from another.",
                                icon: RowIcon("exclamationmark.triangle.fill", .orange)) {
                        Button("Allow…") { ActivityRecorder.requestAccessibility() }
                    }
                }
            }
            SettingsSection("Timeline") {
                SettingsRow("Record my Timeline",
                            description: "Notes each app and window you spend more than 10 seconds in, so the Week Calendar can show what you worked on and what wasn't tracked. It stays on this Mac for two weeks; nothing goes to Harvest unless you log it.",
                            icon: RowIcon("chart.bar.xaxis", .purple), isOn: $records)
                CardDivider()
                SettingsRow("Include the website in browsers", description: "Just the domain", icon: RowIcon("globe", .blue), isOn: $websites)
                    .disabled(!records && !suggests && !autotracks)
                CardDivider()
                SettingsRow("Never record") {
                    TextField("", text: $excluded, prompt: Text("App names, separated by commas"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                CardDivider()
                SettingsRow("Delete everything the Timeline has recorded") {
                    Button("Delete Timeline…") { confirmsDelete = true }
                        .confirmationDialog("Delete everything the Timeline has recorded?", isPresented: $confirmsDelete) {
                            Button("Delete Timeline", role: .destructive) { recorder.deleteTimeline() }
                        }
                }
            }
            SettingsSection("Suggestions") {
                SettingsRow("Suggest tasks from what's on screen",
                            description: "The ask box's first suggestion becomes the task that the app and window you were just in point to: your rules, where you've tracked before, and project or client names in the title.",
                            icon: RowIcon("sparkles", .yellow), isOn: $suggests)
            }
            SettingsSection("Autotracker",
                            footer: "A rule matches when the app's name, the window title or the website contains any of its keywords. It never takes over a timer you started yourself without asking, and only stops timers it started.") {
                SettingsRow("Track with rules", icon: RowIcon("wand.and.stars", .harvestOrange), isOn: $autotracks)
                    .onChange(of: autotracks) { _, on in if on { Notifier.requestPermission() } }
                Group {
                    CardDivider()
                    SettingsRow("When a rule matches") {
                        SettingsPopup(selection: $startsAutomatically, options: [false, true]) { $0 ? "Start the timer" : "Ask first" }
                    }
                    CardDivider()
                    SettingsRow("After time in the window") {
                        SettingsPopup(selection: $delay, choices: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 300]) {
                            "\($0) \($0 == 1 ? "second" : "seconds")"
                        }
                    }
                    CardDivider()
                    SettingsRow("Stop the timer when no rule matches any more", isOn: $stopsWhenUnmatched)
                }
                .disabled(!autotracks)
            }
            SettingsSection("Rules") {
                RulesList(isAdding: $isAddingRule)
            }
            .disabled(!autotracks)
            SettingsSection("Calendar") {
                SettingsRow("Log meetings automatically",
                            description: "Within five minutes of a meeting starting, it's logged to its matched task, and a notification lets you undo. Meetings with no match, no length, or added after they started are left for you.",
                            icon: RowIcon("calendar", .red), isOn: $logsMeetings)
                    .onChange(of: logsMeetings) { _, on in if on { Notifier.requestPermission() } }
            }
        }
        .sheet(isPresented: $isAddingRule) { AddRuleSheet().environment(tracker) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = ActivityRecorder.hasAccessibility
        }
        .onAppear { hasAccessibility = ActivityRecorder.hasAccessibility }
    }
}

/// Your Autotracker rules, top one first, as rows in the card.
private struct RulesList: View {
    @Environment(TimeTracker.self) private var tracker
    @Binding var isAdding: Bool

    var body: some View {
        let rules = tracker.contextMemory.rules
        if rules.isEmpty {
            SettingsRow("No rules yet") { EmptyView() }
        }
        ForEach(rules) { rule in
            let task = tracker.tasks(for: [rule.taskKey]).first
            SettingsRow(rule.keywords,
                        description: task.map { "→ \($0.projectNameParts.name) · \($0.task.name)" } ?? "→ a task you're no longer assigned to") {
                Button { tracker.contextMemory.setRules(rules.filter { $0.id != rule.id }) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this rule")
            }
            CardDivider()
        }
        if rules.isEmpty { CardDivider() }
        SettingsRow("Add a rule") {
            Button("Add Rule…") { isAdding = true }
        }
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
        let results = query.isEmpty ? (tracker.recentTasks + tracker.favoriteTasks).filter { tracker.isAvailable($0.key) }
            : Array(tracker.search(query).prefix(30))
        VStack(alignment: .leading, spacing: 12) {
            Text("New Autotracker Rule").font(.headline)
            TextField("Keywords, e.g. Figma, Pinstripes", text: $keywords)
            Text("Matches when the app's name, window title or website contains any of them.").settingsNote()
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
        .tint(.harvestOrange)
    }
}

// MARK: Support

struct SupportPrefs: View {
    @Environment(TimeTracker.self) private var tracker
    let resetLayout: () -> Void
    var showTour: () -> Void = {}
    @State private var reloaded = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        PrefsPage {
            SettingsSection("Reset App") {
                SettingsRow("Reload from Harvest",
                            description: "\(AppInfo.name) keeps your projects and recent entries in memory. Reload them from Harvest if something looks out of date.",
                            icon: RowIcon("arrow.clockwise", .blue)) {
                    Button(reloaded ? "Reloaded" : "Reload") {
                        Task {
                            await tracker.refresh(force: true)
                            reloaded = true
                        }
                    }
                }
                CardDivider()
                SettingsRow("Reset layout",
                            description: "Put the window size, folded sections and removed suggestions back the way they started.",
                            icon: RowIcon("rectangle.3.group", .purple)) {
                    Button("Reset Layout") {
                        tracker.showHiddenSuggestions()
                        UserDefaults.standard.removeObject(forKey: "collapsedSections")
                        resetLayout()
                    }
                }
                CardDivider()
                SettingsRow("Tour",
                            description: "Walk through the window's main features again, one at a time.",
                            icon: RowIcon("signpost.right.fill", .green)) {
                    Button("Show Tour Again") { showTour() }
                }
            }
            SettingsSection("Account") {
                SettingsRow("Signed in to \(tracker.accountName ?? "Harvest")", icon: RowIcon("person.crop.circle.fill", .harvestOrange)) {
                    Button("Sign Out") { tracker.signOut() }
                }
            }
            SettingsSection("About") {
                SettingsRow("\(AppInfo.name) \(version)", description: "An unofficial client for the Harvest API.",
                            icon: RowIcon("info.circle.fill", .gray)) {
                    Link("Report a Problem…", destination: URL(string: "https://github.com/tractorbeam-user/harvestbeam/issues")!)
                        .foregroundStyle(Color.harvestOrange)
                }
            }
        }
    }
}

// MARK: Layout helpers

private struct PrefsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 22) { content }
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
