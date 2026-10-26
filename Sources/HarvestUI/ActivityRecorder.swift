#if os(macOS)
import AppKit
import ApplicationServices
import HarvestKit
import Observation

/// Watches which app and window are in front, like Toggl's Timeline. It
/// feeds the Timeline (when that's on), suggestions from what's on screen,
/// and the Autotracker. Everything stays on this Mac.
@MainActor @Observable
public final class ActivityRecorder {
    // Preferences, all off until you turn them on, as in Toggl.
    public static let timelineKey = "tracking.timeline"
    public static let websitesKey = "tracking.websites"
    public static let suggestionsKey = "tracking.suggestions"
    public static let excludedKey = "tracking.excludedApps"
    public static let autotrackKey = "tracking.autotrack"
    /// Start a matched rule's timer without asking.
    public static let autotrackStartKey = "tracking.autotrack.start"
    /// Stop a timer the Autotracker started once no rule matches.
    public static let autotrackStopKey = "tracking.autotrack.stop"
    /// Seconds in a window before a rule fires (Toggl's default is 5).
    public static let autotrackDelayKey = "tracking.autotrack.delay"
    public static let autoLogMeetingsKey = "tracking.autoLogMeetings"
    public static let defaultExcluded = "1Password, Keychain Access, Passwords, Messages, FaceTime"

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            timelineKey: false, websitesKey: true, suggestionsKey: false, excludedKey: defaultExcluded,
            autotrackKey: false, autotrackStartKey: false, autotrackStopKey: false, autotrackDelayKey: 5,
            autoLogMeetingsKey: false,
        ])
    }

    /// The app in front right now; nil while it's Harvestbeam, an excluded
    /// app, or you're away.
    public private(set) var current: ScreenContext?
    /// The last app you were in before Harvestbeam, for suggestions when you
    /// open its window.
    public private(set) var lastExternal: ScreenContext?
    /// Bumped whenever the Timeline gains a span.
    public private(set) var revision = 0
    /// Called every tick with what's in front and how long it's been there.
    @ObservationIgnored public var onTick: ((ScreenContext?, TimeInterval) -> Void)?

    @ObservationIgnored private let tracker: TimeTracker
    @ObservationIgnored private let store: TimelineStore
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var currentSince: Date?
    @ObservationIgnored private var spanStart: Date?
    @ObservationIgnored private var spanContext: ScreenContext?
    @ObservationIgnored private var spanKey: TaskKey?
    @ObservationIgnored private var hostCache: (title: String, host: String?, at: Date)?

    public init(tracker: TimeTracker, store: TimelineStore = TimelineStore()) {
        self.tracker = tracker
        self.store = store
        Self.registerDefaults()
        store.prune()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows macOS's prompt to allow Accessibility, which window titles need.
    public static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// The Timeline for a day, including what's being recorded right now.
    public func spans(on day: LocalDate) -> [ActivitySpan] {
        _ = revision
        var spans = store.spans(on: day)
        if UserDefaults.standard.bool(forKey: Self.timelineKey), let start = spanStart, let context = spanContext,
           LocalDate(start) == day, Date().timeIntervalSince(start) > Timeline.minimumSpan {
            spans.append(ActivitySpan(app: context.app, bundleID: context.bundleID, title: context.title,
                                      host: context.host, start: start, end: .now, trackedKey: spanKey))
        }
        return spans
    }

    public func deleteTimeline() {
        store.deleteAll()
        revision += 1
    }

    // MARK: Watching

    private func tick() {
        let defaults = UserDefaults.standard
        let wanted = defaults.bool(forKey: Self.timelineKey) || defaults.bool(forKey: Self.suggestionsKey)
            || defaults.bool(forKey: Self.autotrackKey)
        let now = Date()
        guard wanted, tracker.phase == .ready else {
            closeSpan(at: now)
            current = nil
            return
        }
        // Away: end what was being recorded at the moment you left.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        guard idle < 120, let app = NSWorkspace.shared.frontmostApplication else {
            closeSpan(at: now.addingTimeInterval(-idle))
            setCurrent(nil, at: now)
            return
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier || isExcluded(app) {
            closeSpan(at: now)
            setCurrent(nil, at: now)
            return
        }
        let title = windowTitle(of: app)
        let context = ScreenContext(
            app: app.localizedName ?? "App", bundleID: app.bundleIdentifier ?? "", title: title,
            host: defaults.bool(forKey: Self.websitesKey) ? host(in: app, title: title, now: now) : nil
        )
        let running = tracker.running?.key
        if context != spanContext || running != spanKey {
            closeSpan(at: now)
            spanStart = now
            spanContext = context
            spanKey = running
        }
        setCurrent(context, at: now)
        lastExternal = context
    }

    private func setCurrent(_ context: ScreenContext?, at now: Date) {
        if context != current {
            current = context
            currentSince = context == nil ? nil : now
        }
        onTick?(context, currentSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    private func closeSpan(at end: Date) {
        defer { spanStart = nil; spanContext = nil; spanKey = nil }
        guard let start = spanStart, let context = spanContext, end > start else { return }
        let seconds = end.timeIntervalSince(start)
        // Half a minute in a window with a timer running teaches the
        // suggestions that this window means that task.
        if let key = spanKey, seconds >= 30 { tracker.contextMemory.learn(context, key: key) }
        guard UserDefaults.standard.bool(forKey: Self.timelineKey), seconds > Timeline.minimumSpan else { return }
        store.append(ActivitySpan(app: context.app, bundleID: context.bundleID, title: context.title,
                                  host: context.host, start: start, end: end, trackedKey: spanKey))
        revision += 1
    }

    private func isExcluded(_ app: NSRunningApplication) -> Bool {
        let names = (UserDefaults.standard.string(forKey: Self.excludedKey) ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        let name = (app.localizedName ?? "").lowercased()
        return names.contains(name)
    }

    /// The front window's title, through Accessibility; empty without it.
    private func windowTitle(of app: NSRunningApplication) -> String {
        guard Self.hasAccessibility else { return "" }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title)
        return (title as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static let chromiumBrowsers: [String: String] = [
        "com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave Browser",
        "com.microsoft.edgemac": "Microsoft Edge", "company.thebrowser.Browser": "Arc",
    ]

    /// The site in a browser's front tab: just the domain, never the full
    /// address. Asked at most every few seconds per window, and skipped for
    /// private windows where the browser says so.
    private func host(in app: NSRunningApplication, title: String, now: Date) -> String? {
        guard let id = app.bundleIdentifier else { return nil }
        let script: String
        if id == "com.apple.Safari" {
            script = "tell application \"Safari\" to return URL of front document"
        } else if let name = Self.chromiumBrowsers[id] {
            script = """
            tell application "\(name)"
              if mode of front window is "incognito" then return ""
              return URL of active tab of front window
            end tell
            """
        } else {
            return nil
        }
        if let cached = hostCache, cached.title == title, now.timeIntervalSince(cached.at) < 5 { return cached.host }
        var error: NSDictionary?
        let url = NSAppleScript(source: script)?.executeAndReturnError(&error).stringValue
        let host = url.flatMap { URL(string: $0)?.host }.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        hostCache = (title, host, now)
        return host
    }
}
#endif
