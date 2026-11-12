import Foundation
import Observation

/// App state shared by every screen: who's signed in, the tasks they can track,
/// their recent history, and the running timer.
@MainActor @Observable
public final class TimeTracker {
    public enum Phase: Equatable { case signedOut, loading, ready }

    public private(set) var phase: Phase = .signedOut
    public private(set) var user: HarvestUser?
    public private(set) var company: Company?
    public private(set) var accountName: String?
    public private(set) var tasks: [TrackableTask] = [] {
        didSet {
            tasksByKey = Dictionary(tasks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            searchIndex = Ranking.SearchIndex(tasks: tasks)
            var seen = Set<Int>()
            clients = tasks.compactMap(\.client).filter { seen.insert($0.id).inserted }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
    /// Every client with at least one assignable task, A–Z.
    public private(set) var clients: [NamedRef] = []
    /// The last `historyDays` of the user's time entries, newest first.
    public private(set) var entries: [TimeEntry] = [] {
        didSet {
            usage = Ranking.usageScores(from: entries)
            entryChanges &+= 1
        }
    }
    /// Counts every change to `entries`, so a refresh can tell the list
    /// moved on while it was loading.
    @ObservationIgnored private var entryChanges = 0
    public private(set) var isRefreshing = false
    /// The task whose start/stop request is in flight.
    public private(set) var busyKey: TaskKey?
    /// The note after a change, offering to undo it (or redo an undo).
    public internal(set) var toast: UndoToast?
    /// Changes this session can put back, oldest first; `undo()` takes the last.
    var undoStack: [UndoStep] = []
    var redoStack: [UndoStep] = []
    /// While an undo or redo is on its way to Harvest.
    var isUndoing = false
    public var errorMessage: String?
    /// Bumped whenever the panel opens so the search field can grab focus.
    public private(set) var focusRequest = 0
    /// Whether the latest `focusRequest` should put you in the search box.
    /// ⌥H does, so you can type straight away; nothing else does.
    public private(set) var focusRequestWantsSearch = false

    public let favorites: FavoritesStore
    /// Meetings you've logged or skipped, and where some always go.
    public let meetingMemory: MeetingMemory
    /// Autotracker rules, and which windows you track what in.
    public let contextMemory: ContextMemory
    public let isDemo: Bool
    /// Told about a few milestones, for the app's anonymous usage counts.
    /// Never carries anything from Harvest: just which thing happened.
    public var onUsage: ((UsageEvent) -> Void)?

    @ObservationIgnored var service: (any HarvestService)?
    @ObservationIgnored var toastCounter = 0
    /// Above zero while a change made of smaller ones records itself as one.
    @ObservationIgnored var recordingPaused = 0
    /// Old entry ID → new, for entries deleted and made again by undo.
    @ObservationIgnored var idAliases: [Int: Int] = [:]
    @ObservationIgnored private var lastRefresh: Date?
    // Derived from `tasks` and `entries` when they change, not on every
    // keystroke or redraw.
    @ObservationIgnored private var tasksByKey: [TaskKey: TrackableTask] = [:]
    @ObservationIgnored private(set) var searchIndex = Ranking.SearchIndex(tasks: [])
    @ObservationIgnored private(set) var usage: [TaskKey: Double] = [:]
    /// Earliest day `entries` covers; older weeks are fetched on demand.
    @ObservationIgnored private var loadedFrom: LocalDate?
    /// Latest day `entries` covers; later weeks are fetched on demand.
    @ObservationIgnored private var loadedThrough: LocalDate?
    @ObservationIgnored private var isLoadingHistory = false
    /// Tasks Harvest still lists but marks archived, with which part is.
    private var archivedByKey: [TaskKey: (task: TrackableTask, kind: TaskUnavailability.Kind)] = [:]
    /// Favorites' names as of the last time Harvest listed them.
    @ObservationIgnored private var rememberedTasks: [TaskKey: TrackableTask]
    @ObservationIgnored private let defaults: UserDefaults

    static let historyDays = 60
    /// Entries logged ahead (meetings later this week, next week's plans).
    static let futureDays = 28

    public init(
        service: (any HarvestService)?, accountName: String?, favorites: FavoritesStore,
        meetingMemory: MeetingMemory = MeetingMemory(), contextMemory: ContextMemory = ContextMemory(),
        isDemo: Bool = false, defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.rememberedTasks = RememberedTasks.load(from: defaults)
        self.service = service
        self.accountName = accountName
        self.favorites = favorites
        self.meetingMemory = meetingMemory
        self.contextMemory = contextMemory
        self.isDemo = isDemo
        self.phase = service == nil ? .signedOut : .loading
        favorites.onChange = { [weak self] before, after in self?.favoritesChanged(from: before, to: after) }
    }

    /// Signs in with the token saved in the Keychain, if any.
    public static func live() -> TimeTracker {
        let credentials = CredentialStore.load()
        return TimeTracker(
            service: credentials.map { HarvestClient(token: $0.token, accountID: $0.accountID) },
            accountName: credentials?.accountName,
            favorites: FavoritesStore()
        )
    }

    /// Sample data, no network. Launch with `--demo` to try the UI.
    public static func demo() -> TimeTracker {
        let defaults = UserDefaults(suiteName: "HarvestBarDemo") ?? .standard
        return TimeTracker(
            service: DemoHarvestService(),
            accountName: "Tractorbeam (demo)",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults),
            contextMemory: ContextMemory(defaults: defaults),
            isDemo: true, defaults: defaults
        )
    }

    #if DEBUG
    /// The demo with an archived project in its history and favorites, for
    /// snapshots of how archived work looks.
    public static func demoWithArchivedWork() -> TimeTracker {
        let defaults = UserDefaults(suiteName: "HarvestBarDemoArchived") ?? .standard
        defaults.removeObject(forKey: "favorites.v1")
        defaults.removeObject(forKey: RememberedTasks.key)
        return TimeTracker(
            service: DemoHarvestService(includesArchivedWork: true),
            accountName: "Tractorbeam (demo)",
            favorites: FavoritesStore(defaults: defaults, syncWithICloud: false),
            meetingMemory: MeetingMemory(defaults: defaults),
            contextMemory: ContextMemory(defaults: defaults),
            isDemo: true, defaults: defaults
        )
    }
    #endif

    // MARK: Derived lists

    public var running: TimeEntry? { entries.first(where: \.isRunning) }

    public var runningTask: TrackableTask? { running.map(task(for:)) }

    public func task(for entry: TimeEntry) -> TrackableTask {
        tasksByKey[entry.key] ?? TrackableTask(project: entry.project, client: entry.client, task: entry.task)
    }

    public var todayEntries: [TimeEntry] {
        let today = LocalDate()
        return entries.filter { $0.spentDate == today }
    }

    public func todaySeconds(at now: Date = .now) -> TimeInterval {
        seconds(on: LocalDate(), at: now)
    }

    /// A day's entries in the order they were created, like Harvest's day view.
    public func entries(on day: LocalDate) -> [TimeEntry] {
        entries.filter { $0.spentDate == day }.sorted { $0.createdAt < $1.createdAt }
    }

    public func seconds(on day: LocalDate, at now: Date = .now) -> TimeInterval {
        entries.reduce(0) { $1.spentDate == day ? $0 + $1.elapsed(at: now) : $0 }
    }

    /// The weekday the account's weeks start on (`Calendar` numbering).
    public var firstWeekday: Int { company?.firstWeekday ?? 2 }

    /// Fetches later entries when you page forward past what's loaded.
    public func ensureLoaded(through day: LocalDate) async {
        guard await waitForHistory() else { return }
        guard let service, let user, let loadedThrough, day > loadedThrough else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let through = day.adding(days: 28)
        do {
            let later = try await service.timeEntries(userID: user.id, from: loadedThrough.adding(days: 1), to: through)
            let known = Set(entries.map(\.id))
            entries = Self.sorted(entries + later.filter { !known.contains($0.id) })
            self.loadedThrough = through
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Lets a load of other weeks already on its way finish first, so paging
    /// quickly loads each week instead of skipping the ones in between.
    /// False if this load was called off meanwhile.
    private func waitForHistory() async -> Bool {
        while isLoadingHistory {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return false }
        }
        return true
    }

    /// Fetches older entries when you page back past what's loaded.
    public func ensureLoaded(from day: LocalDate) async {
        guard await waitForHistory() else { return }
        guard let service, let user, let loadedFrom, day < loadedFrom else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let from = day.adding(days: -28) // a few weeks at a time
        do {
            let older = try await service.timeEntries(userID: user.id, from: from, to: loadedFrom.adding(days: -1))
            let known = Set(entries.map(\.id))
            entries = Self.sorted(entries + older.filter { !known.contains($0.id) })
            self.loadedFrom = from
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starred tasks in order. Archived ones stay, so they can show as
    /// archived instead of quietly vanishing; check `unavailability(of:)`.
    public var favoriteTasks: [TrackableTask] {
        favorites.keys.compactMap { tasksByKey[$0] ?? unavailableTask($0) }
    }

    /// Why time can't be tracked to `key` any more, or nil when it can (or
    /// before Harvest has said what you're assigned to).
    public func unavailability(of key: TaskKey) -> TaskUnavailability? {
        guard phase == .ready, !tasks.isEmpty, key.taskID >= 0, tasksByKey[key] == nil else { return nil }
        return TaskUnavailability(kind: archivedByKey[key]?.kind ?? .notAssigned)
    }

    public func isAvailable(_ key: TaskKey) -> Bool { unavailability(of: key) == nil }

    /// Names for a task Harvest no longer offers: from its archived
    /// assignment, your entries on it, or what was remembered when starred.
    private func unavailableTask(_ key: TaskKey) -> TrackableTask? {
        guard unavailability(of: key) != nil else { return nil }
        if let archived = archivedByKey[key] { return archived.task }
        if let entry = entries.first(where: { $0.key == key }) { return task(for: entry) }
        return rememberedTasks[key]
    }

    /// Keeps the names of today's favorites, so they can still be shown if
    /// their project is archived later.
    private func rememberFavorites() {
        let known = favorites.keys.compactMap { tasksByKey[$0] ?? rememberedTasks[$0] }
        let updated = Dictionary(known.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        guard updated != rememberedTasks else { return }
        rememberedTasks = updated
        RememberedTasks.save(known, to: defaults)
    }

    public func tasks(for keys: [TaskKey]) -> [TrackableTask] {
        keys.compactMap { tasksByKey[$0] }
    }

    /// A client's tasks, by project then task name.
    public func tasks(forClient id: Int) -> [TrackableTask] {
        tasks.filter { $0.client?.id == id }.sorted {
            ($0.project.name, $0.task.name) < ($1.project.name, $1.task.name)
        }
    }

    public var recentTasks: [TrackableTask] {
        Ranking.recent(from: entries, excluding: favorites.set, limit: 4).compactMap { tasksByKey[$0] ?? unavailableTask($0) }
    }

    /// Tasks removed from Suggested; the next best ones take their place.
    public private(set) var hiddenSuggestions: Set<TaskKey> = Set(
        (UserDefaults.standard.stringArray(forKey: TimeTracker.hiddenSuggestionsKey) ?? []).compactMap(TaskKey.init)
    )
    private static let hiddenSuggestionsKey = "hiddenSuggestions.v1"

    public func hideSuggestion(_ key: TaskKey) {
        hiddenSuggestions.insert(key)
        UserDefaults.standard.set(hiddenSuggestions.map(\.description), forKey: Self.hiddenSuggestionsKey)
    }

    public func showHiddenSuggestions() {
        hiddenSuggestions = []
        UserDefaults.standard.removeObject(forKey: Self.hiddenSuggestionsKey)
    }

    public var suggestedTasks: [TrackableTask] {
        let shown = favorites.set.union(recentTasks.map(\.key)).union(hiddenSuggestions)
        let assignable = usage.filter { tasksByKey[$0.key] != nil }
        return Ranking.suggested(scores: assignable, excluding: shown, limit: 4).compactMap { tasksByKey[$0] }
    }

    public func search(_ query: String) -> [TrackableTask] {
        Array(searchIndex.search(query, usage: usage, favorites: favorites.set).prefix(100))
    }

    /// The timer you stopped last today, when nothing is running, so it can
    /// be resumed with one click. Without one (just opened), today's most
    /// recently changed entry.
    public var pausedEntry: TimeEntry? {
        guard running == nil else { return nil }
        let today = todayEntries
        if let id = lastStoppedID, let entry = today.first(where: { $0.id == id }) { return entry }
        return today.max { $0.updatedAt < $1.updatedAt }
    }
    /// The entry whose timer this app stopped last: an entry logged or
    /// edited since (⌘N, a meeting) doesn't take its place for Resume.
    private var lastStoppedID: Int?

    public var harvestWebURL: URL? {
        guard let base = company?.baseUri else { return URL(string: "https://id.getharvest.com") }
        return URL(string: base + "/time")
    }

    // MARK: Lifecycle

    /// Call when the panel or app comes to the front.
    public func didAppear(focusSearch: Bool = false) {
        focusRequestWantsSearch = focusSearch
        focusRequest += 1
        Task { await refresh() }
    }

    public func refresh(force: Bool = false) async {
        guard let service, !isRefreshing else { return }
        if !force, phase == .ready, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let changesAtStart = entryChanges
        do {
            let me: HarvestUser
            if let user { me = user } else { me = try await service.currentUser(); user = me }
            if company == nil { company = try? await service.company() }

            let today = LocalDate()
            let from = today.adding(days: -Self.historyDays)
            let through = today.adding(days: Self.futureDays)
            async let assignments = service.projectAssignments()
            async let history = service.timeEntries(userID: me.id, from: from, to: through)
            let (loadedAssignments, loadedEntries) = try await (assignments, history)

            archivedByKey = ProjectAssignment.archivedTasks(from: loadedAssignments)
            tasks = ProjectAssignment.trackableTasks(from: loadedAssignments)
            // A change made while this loaded, or a start or stop still on
            // its way to Harvest, wins over a list fetched before it
            // landed; the next refresh picks it all up.
            if phase != .ready || (busyKey == nil && entryChanges == changesAtStart) {
                // Keep any older or later weeks already paged in.
                entries = Self.sorted(loadedEntries + entries.filter { $0.spentDate < from || $0.spentDate > through })
                lastRefresh = .now
            } else {
                lastRefresh = nil
            }
            loadedFrom = min(loadedFrom ?? from, from)
            loadedThrough = max(loadedThrough ?? through, through)
            phase = .ready
            errorMessage = nil
            rememberFavorites()
        } catch HarvestError.unauthorized where !isDemo {
            signOut()
            errorMessage = HarvestError.unauthorized.errorDescription
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Timer actions

    /// Starts tracking `task`, or pauses it if it's the one already running.
    /// Reuses today's entry for the same task, like Harvest's own timer does.
    public func toggle(_ task: TrackableTask) async {
        if running?.key == task.key {
            await pause()
            return
        }
        if let reason = unavailability(of: task.key) {
            errorMessage = "Can't start \(task.projectNameParts.name) · \(task.task.name). " + reason.detail
            return
        }
        guard let service, busyKey == nil else { return }
        busyKey = task.key
        defer { busyKey = nil }
        let stopped = running
        let today = LocalDate()
        let existing = entries.first(where: { $0.key == task.key && $0.spentDate == today })
        // Show the switch straight away, then fill in Harvest's own numbers
        // when it answers: the old timer stops and the new one runs (a
        // stand-in entry until Harvest gives the real one).
        let now = Date()
        if let current = stopped { upsert(current.locallyStopped(at: now)) }
        upsert(existing?.locallyRestarted(at: now) ?? TimeEntry(
            id: Self.pendingEntryID, spentDate: today, project: task.project, task: task.task, client: task.client,
            hours: 0, hoursWithoutTimer: 0, isRunning: true, timerStartedAt: now, createdAt: now, updatedAt: now
        ))
        defer { entries.removeAll { $0.id == Self.pendingEntryID } }
        var stopConfirmed = false
        do {
            if let current = stopped {
                upsert(try await service.stopTimer(id: current.id))
                stopConfirmed = true
            }
            let started: TimeEntry
            if let existing {
                started = try await service.restartTimer(id: existing.id)
            } else {
                started = try await service.startTimer(projectID: task.project.id, taskID: task.task.id, spentDate: today, notes: nil)
            }
            upsert(started)
            errorMessage = nil
            record("Started \(shortName(for: task))", startOp(started: started, wasNew: existing == nil, stopped: stopped))
            onUsage?(.timerStarted)
        } catch {
            // Put back what Harvest didn't take: the old timer runs again
            // unless it really stopped, and the new one never started.
            entries.removeAll { $0.id == Self.pendingEntryID }
            if let existing { upsert(existing) }
            if let stopped, !stopConfirmed { upsert(stopped) }
            await recover(from: error)
        }
    }

    /// Stops the running timer. Harvest keeps the entry, so `resume()` (or
    /// starting the same task again today) carries on where it left off.
    public func pause() async {
        guard let service, let current = running, busyKey == nil else { return }
        busyKey = current.key
        defer { busyKey = nil }
        // Stopped on screen straight away; Harvest's numbers follow.
        upsert(current.locallyStopped(at: Date()))
        lastStoppedID = current.id
        do {
            upsert(try await service.stopTimer(id: current.id))
            errorMessage = nil
            record("Paused \(shortName(for: current))", .restart(entryID: current.id))
        } catch {
            upsert(current)
            await recover(from: error)
        }
    }

    /// Harvest rejects stopping or restarting a timer that already changed
    /// elsewhere (Harvest's own apps, the web). Reload instead of showing that
    /// as an error, so the bar matches Harvest again.
    /// Edits (`isTimer` false) still say what Harvest refused, after the
    /// reload, so a change that didn't stick never looks like it did.
    private func recover(from error: Error, isTimer: Bool = true) async {
        if case HarvestError.server(let status, _) = error, status == 422 || status == 404 {
            busyKey = nil
            await refresh(force: true)
            errorMessage = isTimer ? nil : error.localizedDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }

    /// Restarts a specific entry (from the day view), or pauses it if running.
    public func toggle(_ entry: TimeEntry) async {
        if entry.isRunning {
            await pause()
            return
        }
        if let message = cantChangeMessage(entry) {
            errorMessage = message
            return
        }
        guard let service, busyKey == nil else { return }
        busyKey = entry.key
        defer { busyKey = nil }
        let stopped = running
        let now = Date()
        // The switch shows straight away, as it does from a tile.
        if let current = stopped { upsert(current.locallyStopped(at: now)) }
        upsert(entry.locallyRestarted(at: now))
        var stopConfirmed = false
        do {
            if let current = stopped {
                upsert(try await service.stopTimer(id: current.id))
                stopConfirmed = true
            }
            let started = try await service.restartTimer(id: entry.id)
            upsert(started)
            errorMessage = nil
            record("Started \(shortName(for: entry))", startOp(started: started, wasNew: false, stopped: stopped))
        } catch {
            upsert(entry)
            if let stopped, !stopConfirmed { upsert(stopped) }
            await recover(from: error)
        }
    }

    /// Toggl's Continue/Stop: stops the running timer; otherwise starts the
    /// most recent entry again (today's, or a fresh one today with the same
    /// task and notes when it was on another day).
    public func continueOrStop() async {
        if running != nil {
            await pause()
        } else if let paused = pausedEntry {
            await toggle(paused)
        } else if let last = entries.first(where: { $0.spentDate <= LocalDate() }) {
            await addEntry(task: task(for: last), on: LocalDate(), notes: last.notes ?? "", hours: nil)
        }
    }

    public func resume() async {
        guard let entry = pausedEntry else { return }
        await toggle(task(for: entry))
    }

    /// Accounts set to track start and end times keep an entry's hours as
    /// the gap between them, so new lengths go in as times.
    var tracksStartAndEnd: Bool { company?.wantsTimestampTimers == true }

    /// The start and end times that give `entry` a new length: it keeps its
    /// start, and the end moves. Nil on duration accounts.
    func times(for entry: TimeEntry, hours: Double) -> ClockTimes? {
        guard tracksStartAndEnd else { return nil }
        if let start = entry.startedTime { return ClockTime.times(startingAt: start, hours: hours) }
        return entry.timerStartedAt.flatMap { ClockTime.times(from: $0, hours: hours) }
    }

    /// What to say when someone tries to restart or change an entry Harvest
    /// won't let change; nil when it can.
    public func cantChangeMessage(_ entry: TimeEntry) -> String? {
        if entry.isPending { return "Harvest is still starting this timer. Try again in a moment." }
        if let lock = entry.lock { return "Can't change this entry: it's \(lock.title.lowercased()). " + lock.detail }
        if let reason = unavailability(of: entry.key) { return "Can't restart this entry. " + reason.detail }
        return nil
    }

    /// Whether Harvest took the change.
    @discardableResult
    public func updateEntry(_ entry: TimeEntry, task: TrackableTask, notes: String, hours: Double?) async -> Bool {
        guard let service, !entry.isPending else { return false }
        if let lock = entry.lock {
            errorMessage = "Can't change this entry: it's \(lock.title.lowercased()). " + lock.detail
            return false
        }
        if task.key != entry.key, let reason = unavailability(of: task.key) {
            errorMessage = "Can't move this entry there. " + reason.detail
            return false
        }
        do {
            var target = entry
            var newHours = entry.isRunning ? nil : hours
            // Typing a new time on a running timer settles it: stop the timer
            // (Harvest won't set hours on a running one) and keep the new time.
            if entry.isRunning, let hours, abs(hours - entry.elapsed() / 3600) > 1.0 / 120 {
                target = try await service.stopTimer(id: entry.id)
                newHours = hours
            }
            let updated = try await service.updateEntry(
                id: target.id, projectID: task.project.id, taskID: task.task.id, notes: notes,
                hours: newHours, times: newHours.flatMap { times(for: target, hours: $0) }
            )
            upsert(updated)
            if let label = editLabel(from: entry, to: updated) { record(label, .revert(entry)) }
            // Say so when Harvest kept a different length, rather than
            // quietly showing the old time again.
            if let newHours, abs(updated.hours - newHours) > 1.0 / 60 {
                errorMessage = "Harvest kept this entry at \(TimeFormat.hoursMinutes(updated.hours * 3600)), not \(TimeFormat.hoursMinutes(newHours * 3600))."
                    + (tracksStartAndEnd ? " Your account tracks start and end times; change them in Harvest." : "")
            } else {
                errorMessage = nil
            }
            return true
        } catch {
            await recover(from: error, isTimer: false)
            return false
        }
    }

    /// Moves `seconds` of `entry` to `task` on the same day: shortens this
    /// entry and logs the rest as a new one there. A running timer keeps
    /// running. If the new entry can't be made, the old one gets its time back.
    /// Returns whether it worked.
    @discardableResult
    public func moveTime(_ seconds: TimeInterval, from entry: TimeEntry, to task: TrackableTask, notes: String = "") async -> Bool {
        guard let service, !entry.isPending else { return false }
        // Before touching this entry: time can't land on an archived task.
        if let reason = unavailability(of: task.key) {
            errorMessage = "Can't move time to \(task.projectNameParts.name) · \(task.task.name). " + reason.detail
            return false
        }
        if let lock = entry.lock {
            errorMessage = "This entry is \(lock.title.lowercased()), so its time can't be moved."
            return false
        }
        let moving = (seconds / 60).rounded() / 60
        let had = entry.elapsed() / 3600
        guard moving >= 1.0 / 60 else { errorMessage = "Move at least a minute."; return false }
        guard moving <= had - 1.0 / 60 || (!entry.isRunning && moving <= had) else {
            errorMessage = "This entry only has \(TimeFormat.hoursMinutes(had * 3600)) to move."
            return false
        }
        guard await waitUntilIdle() else {
            errorMessage = "Harvest is still working on your last change. Try again in a moment."
            return false
        }
        do {
            // Harvest won't change the hours on a running timer: stop it, take
            // the time off, and start it again.
            let wasRunning = entry.isRunning
            let source = wasRunning ? try await service.stopTimer(id: entry.id) : entry
            let original = source.hours
            let left = max(0, original - moving)
            var shortened = try await service.updateEntry(
                id: source.id, projectID: source.project.id, taskID: source.task.id,
                notes: source.notes ?? "", hours: left, times: times(for: source, hours: left)
            )
            if wasRunning { shortened = try await service.restartTimer(id: shortened.id) }
            upsert(shortened)
            let added = await withoutRecording {
                await addEntry(task: task, on: entry.spentDate, notes: notes, hours: moving)
            }
            guard let added else {
                // Put the time back rather than lose it.
                var restored = try await service.updateEntry(
                    id: shortened.id, projectID: shortened.project.id, taskID: shortened.task.id,
                    notes: shortened.notes ?? "", hours: wasRunning ? nil : original, times: nil
                )
                if wasRunning {
                    restored = try await service.stopTimer(id: restored.id)
                    restored = try await service.updateEntry(
                        id: restored.id, projectID: restored.project.id, taskID: restored.task.id,
                        notes: restored.notes ?? "", hours: original, times: times(for: restored, hours: original))
                    restored = try await service.restartTimer(id: restored.id)
                }
                upsert(restored)
                errorMessage = "Couldn't log the time on \(task.task.name), so it stayed where it was."
                return false
            }
            errorMessage = nil
            // One undo puts both halves back: the new entry goes, the old one
            // gets its time back.
            record("Moved \(TimeFormat.hoursMinutes(moving * 3600)) to \(shortName(for: task))",
                   .group([.delete(entryID: added.id), .revert(entry)]))
            return true
        } catch {
            await recover(from: error, isTimer: false)
            return false
        }
    }

    /// Takes time you were away off the running timer, optionally stopping it.
    public func removeIdleTime(_ seconds: TimeInterval, keepRunning: Bool) async {
        guard let service, let current = running else { return }
        do {
            let stopped = try await service.stopTimer(id: current.id)
            let hours = max(0, stopped.hours - seconds / 3600)
            var updated = try await service.updateEntry(
                id: stopped.id, projectID: stopped.project.id, taskID: stopped.task.id,
                notes: stopped.notes ?? "", hours: hours, times: times(for: stopped, hours: hours)
            )
            if keepRunning { updated = try await service.restartTimer(id: updated.id) }
            upsert(updated)
            errorMessage = nil
            record("Removed \(TimeFormat.hoursMinutes(seconds)) idle time from \(shortName(for: current))", .revert(current))
        } catch {
            await recover(from: error, isTimer: false)
        }
    }

    /// Adds an entry to `day`: a running timer when no hours are given (today
    /// only), otherwise a stopped entry with those hours. Returns the entry.
    /// On accounts that track start and end times it starts at `startingAt`
    /// (a meeting's start), else ends now (today) or starts at 9:00 (other days).
    @discardableResult
    public func addEntry(task: TrackableTask, on day: LocalDate, notes: String, hours: Double?, startingAt: Date? = nil) async -> TimeEntry? {
        guard let service else { return nil }
        if let reason = unavailability(of: task.key) {
            errorMessage = "Can't add time to \(task.projectNameParts.name) · \(task.task.name). " + reason.detail
            return nil
        }
        // Saving right after starting or pausing a timer waits its turn,
        // instead of quietly doing nothing.
        guard await waitUntilIdle() else {
            errorMessage = "Harvest is still working on your last change. Try again in a moment."
            return nil
        }
        busyKey = task.key
        defer { busyKey = nil }
        let notes = notes.isEmpty ? nil : notes
        do {
            let added: TimeEntry
            var stopped: TimeEntry?
            if let hours {
                var times: ClockTimes?
                if tracksStartAndEnd {
                    let start = startingAt ?? (day == LocalDate() ? Date().addingTimeInterval(-hours * 3600) : (Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day.date()) ?? day.date()))
                    times = ClockTime.times(from: start, hours: hours)
                }
                added = try await service.createEntry(projectID: task.project.id, taskID: task.task.id, spentDate: day,
                                                      notes: notes, hours: hours, times: times)
            } else {
                stopped = running
                if let current = running { upsert(try await service.stopTimer(id: current.id)) }
                added = try await service.startTimer(projectID: task.project.id, taskID: task.task.id, spentDate: day, notes: notes)
            }
            upsert(added)
            errorMessage = nil
            if let hours {
                record("Added \(TimeFormat.hoursMinutes(hours * 3600)) to \(shortName(for: task))", .delete(entryID: added.id))
            } else {
                record("Started \(shortName(for: task))", startOp(started: added, wasNew: true, stopped: stopped))
            }
            return added
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    public func deleteEntry(_ entry: TimeEntry) async {
        guard let service else { return }
        if let lock = entry.lock {
            errorMessage = "Can't delete this entry: it's \(lock.title.lowercased()). " + lock.detail
            return
        }
        do {
            try await service.deleteEntry(id: entry.id)
            entries = entries.filter { $0.id != entry.id }
            errorMessage = nil
            // Undo makes it again: same task, day, notes and time.
            record("Deleted \(shortName(for: entry)) · \(TimeFormat.hoursMinutes(entry.elapsed()))", .recreate(entry))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The day's other entries for exactly the same project and task, which
    /// Merge would fold into this one. Locked entries are left out.
    public func sameTaskEntries(as entry: TimeEntry) -> [TimeEntry] {
        entries(on: entry.spentDate).filter { $0.id != entry.id && $0.key == entry.key && $0.lock == nil }
    }

    /// Folds the day's entries for the same task into one: the running one
    /// (or else the earliest) keeps all the time and every distinct note, the
    /// rest are deleted. One undo puts them all back.
    @discardableResult
    public func mergeSameTaskEntries(into entry: TimeEntry) async -> Bool {
        guard let service, !entry.isPending else { return false }
        guard await waitUntilIdle() else {
            errorMessage = "Harvest is still working on your last change. Try again in a moment."
            return false
        }
        // As they are now: a timer may have started or stopped while waiting.
        let entry = entries.first { $0.id == entry.id } ?? entry
        let group = [entry] + sameTaskEntries(as: entry)
        guard group.count > 1, entry.lock == nil else { return false }
        // Holds off timer clicks until it's done, so none lands mid-merge.
        busyKey = entry.key
        defer { busyKey = nil }
        let keeper = group.first(where: \.isRunning) ?? group.min { $0.createdAt < $1.createdAt }!
        let others = group.filter { $0.id != keeper.id }
        var notes: [String] = []
        for item in [keeper] + others {
            let note = (item.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty && !notes.contains(note) { notes.append(note) }
        }
        do {
            let wasRunning = keeper.isRunning
            let base = wasRunning ? try await service.stopTimer(id: keeper.id) : keeper
            let total = base.hours + others.reduce(0) { $0 + $1.hours }
            var merged = try await service.updateEntry(
                id: base.id, projectID: base.project.id, taskID: base.task.id,
                notes: notes.joined(separator: "; "), hours: total, times: times(for: base, hours: total)
            )
            if wasRunning { merged = try await service.restartTimer(id: merged.id) }
            upsert(merged)
            for other in others {
                try await service.deleteEntry(id: other.id)
                entries = entries.filter { $0.id != other.id }
            }
            errorMessage = nil
            record("Merged \(group.count) \(shortName(for: keeper)) entries · \(TimeFormat.hoursMinutes(total * 3600))",
                   .group([.revert(keeper)] + others.map { .recreate($0) }))
            return true
        } catch {
            // Part of it may have gone through: show what Harvest has now.
            busyKey = nil
            await refresh(force: true)
            errorMessage = "The merge didn't finish. " + error.localizedDescription
            return false
        }
    }

    /// Harvest's day view for an entry's date.
    public func harvestURL(for day: LocalDate) -> URL? {
        guard let base = company?.baseUri else { return harvestWebURL }
        return URL(string: base + String(format: "/time/day/%04d/%02d/%02d", day.year, day.month, day.day))
    }

    public func updateNotes(_ notes: String, for entry: TimeEntry) async {
        guard let service, notes != (entry.notes ?? "") else { return }
        do {
            upsert(try await service.updateNotes(id: entry.id, notes: notes))
            record("Changed notes on \(shortName(for: entry))", .revert(entry))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Sign in / out

    public static func harvestAccounts(for token: String) async throws -> [HarvestAccount] {
        try await HarvestClient.accounts(token: token)
    }

    public func signIn(token: String, account: HarvestAccount) async throws {
        let client = HarvestClient(token: token, accountID: account.id)
        let me = try await client.currentUser()
        try CredentialStore.save(Credentials(token: token, accountID: account.id, accountName: account.name))
        service = client
        user = me
        company = nil
        accountName = account.name
        phase = .loading
        errorMessage = nil
        await refresh(force: true)
        onUsage?(.signedIn)
    }

    public func signOut() {
        if !isDemo { CredentialStore.delete() }
        service = nil
        user = nil
        company = nil
        accountName = nil
        tasks = []
        entries = []
        loadedFrom = nil
        loadedThrough = nil
        lastRefresh = nil
        phase = .signedOut
        clearUndoHistory()
    }

    /// Words for an edit, or nil when nothing changed.
    private func editLabel(from old: TimeEntry, to new: TimeEntry) -> String? {
        if old.key != new.key { return "Moved an entry to \(shortName(for: new))" }
        if old.isRunning != new.isRunning || abs(old.elapsed() - new.elapsed()) >= 60 {
            return "Changed \(shortName(for: new)) to \(TimeFormat.hoursMinutes(new.elapsed()))"
        }
        if (old.notes ?? "") != (new.notes ?? "") { return "Changed notes on \(shortName(for: new))" }
        return nil
    }

    // MARK: Helpers

    /// Waits up to ten seconds for a start or stop already on its way to
    /// Harvest; false if it's still going.
    private func waitUntilIdle() async -> Bool {
        var waited = 0
        while busyKey != nil, waited < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        return busyKey == nil
    }

    func removeEntry(id: Int) {
        entries = entries.filter { $0.id != id }
    }

    /// The stand-in for a timer that's starting, until Harvest says its id.
    nonisolated static let pendingEntryID = -1
}

extension TimeEntry {
    /// A timer that's starting: on screen already, but Harvest hasn't given
    /// it an id yet, so it can't be edited, split or deleted.
    public var isPending: Bool { id == TimeTracker.pendingEntryID }
}

extension TimeTracker {
    func upsert(_ entry: TimeEntry) {
        var updated = entries.filter { $0.id != entry.id }
        updated.append(entry)
        entries = Self.sorted(updated)
    }

    private static func sorted(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.sorted { ($0.spentDate, $0.updatedAt) > ($1.spentDate, $1.updatedAt) }
    }
}
