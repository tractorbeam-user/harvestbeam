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
        didSet { usage = Ranking.usageScores(from: entries) }
    }
    public private(set) var isRefreshing = false
    /// The task whose start/stop request is in flight.
    public private(set) var busyKey: TaskKey?
    /// The entry most recently deleted, until it's undone or dismissed.
    public var lastDeleted: TimeEntry?
    public var errorMessage: String?
    /// Bumped whenever the panel opens so the search field can grab focus.
    public private(set) var focusRequest = 0
    /// Whether the latest `focusRequest` should put you in the search box.
    /// ⌥H does, so you can type straight away; a menu bar click doesn't.
    public private(set) var focusRequestWantsSearch = true

    public let favorites: FavoritesStore
    public let isDemo: Bool

    @ObservationIgnored private var service: (any HarvestService)?
    @ObservationIgnored private var lastRefresh: Date?
    // Derived from `tasks` and `entries` when they change, not on every
    // keystroke or redraw.
    @ObservationIgnored private var tasksByKey: [TaskKey: TrackableTask] = [:]
    @ObservationIgnored private(set) var searchIndex = Ranking.SearchIndex(tasks: [])
    @ObservationIgnored private(set) var usage: [TaskKey: Double] = [:]
    /// Earliest day `entries` covers; older weeks are fetched on demand.
    @ObservationIgnored private var loadedFrom: LocalDate?
    @ObservationIgnored private var isLoadingHistory = false

    static let historyDays = 60

    public init(service: (any HarvestService)?, accountName: String?, favorites: FavoritesStore, isDemo: Bool = false) {
        self.service = service
        self.accountName = accountName
        self.favorites = favorites
        self.isDemo = isDemo
        self.phase = service == nil ? .signedOut : .loading
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
            isDemo: true
        )
    }

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

    /// Fetches older entries when you page back past what's loaded.
    public func ensureLoaded(from day: LocalDate) async {
        guard let service, let user, let loadedFrom, day < loadedFrom, !isLoadingHistory else { return }
        isLoadingHistory = true
        defer { isLoadingHistory = false }
        let from = day.adding(days: -28) // a few weeks at a time
        do {
            let older = try await service.timeEntries(userID: user.id, from: from, to: loadedFrom.adding(days: -1))
            let known = Set(entries.map(\.id))
            entries = Self.sorted(entries + older.filter { !known.contains($0.id) })
            self.loadedFrom = from
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public var favoriteTasks: [TrackableTask] {
        favorites.keys.compactMap { tasksByKey[$0] }
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
        Ranking.recent(from: entries, excluding: favorites.set, limit: 4).compactMap { tasksByKey[$0] }
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

    /// Today's most recently tracked entry, when nothing is running, so it can
    /// be resumed with one click.
    public var pausedEntry: TimeEntry? {
        guard running == nil else { return nil }
        return todayEntries.max { $0.updatedAt < $1.updatedAt }
    }

    public var harvestWebURL: URL? {
        guard let base = company?.baseUri else { return URL(string: "https://id.getharvest.com") }
        return URL(string: base + "/time")
    }

    // MARK: Lifecycle

    /// Call when the panel or app comes to the front.
    public func didAppear(focusSearch: Bool = true) {
        focusRequestWantsSearch = focusSearch
        focusRequest += 1
        Task { await refresh() }
    }

    public func refresh(force: Bool = false) async {
        guard let service, !isRefreshing else { return }
        if !force, phase == .ready, let lastRefresh, Date().timeIntervalSince(lastRefresh) < 30 { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let me: HarvestUser
            if let user { me = user } else { me = try await service.currentUser(); user = me }
            if company == nil { company = try? await service.company() }

            let today = LocalDate()
            let from = today.adding(days: -Self.historyDays)
            async let assignments = service.projectAssignments()
            async let history = service.timeEntries(userID: me.id, from: from, to: today)
            let (loadedAssignments, loadedEntries) = try await (assignments, history)

            tasks = ProjectAssignment.trackableTasks(from: loadedAssignments)
            // Keep any older weeks already paged in.
            entries = Self.sorted(loadedEntries + entries.filter { $0.spentDate < from })
            loadedFrom = min(loadedFrom ?? from, from)
            lastRefresh = .now
            phase = .ready
            errorMessage = nil
        } catch HarvestError.unauthorized where !isDemo {
            signOut()
            errorMessage = HarvestError.unauthorized.errorDescription
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
        guard let service, busyKey == nil else { return }
        busyKey = task.key
        defer { busyKey = nil }
        do {
            if let current = running {
                upsert(try await service.stopTimer(id: current.id))
            }
            let today = LocalDate()
            let started: TimeEntry
            if let existing = entries.first(where: { $0.key == task.key && $0.spentDate == today }) {
                started = try await service.restartTimer(id: existing.id)
            } else {
                started = try await service.startTimer(projectID: task.project.id, taskID: task.task.id, spentDate: today, notes: nil)
            }
            upsert(started)
            errorMessage = nil
        } catch {
            await recover(from: error)
        }
    }

    /// Stops the running timer. Harvest keeps the entry, so `resume()` (or
    /// starting the same task again today) carries on where it left off.
    public func pause() async {
        guard let service, let current = running, busyKey == nil else { return }
        busyKey = current.key
        defer { busyKey = nil }
        do {
            upsert(try await service.stopTimer(id: current.id))
            errorMessage = nil
        } catch {
            await recover(from: error)
        }
    }

    /// Harvest rejects stopping or restarting a timer that already changed
    /// elsewhere (Harvest's own apps, the web). Reload instead of showing that
    /// as an error, so the bar matches Harvest again.
    private func recover(from error: Error) async {
        if case HarvestError.server(let status, _) = error, status == 422 || status == 404 {
            busyKey = nil
            await refresh(force: true)
            if case HarvestError.server = error { errorMessage = nil }
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
        guard let service, busyKey == nil else { return }
        busyKey = entry.key
        defer { busyKey = nil }
        do {
            if let current = running {
                upsert(try await service.stopTimer(id: current.id))
            }
            upsert(try await service.restartTimer(id: entry.id))
            errorMessage = nil
        } catch {
            await recover(from: error)
        }
    }

    public func resume() async {
        guard let entry = pausedEntry else { return }
        await toggle(task(for: entry))
    }

    public func updateEntry(_ entry: TimeEntry, task: TrackableTask, notes: String, hours: Double?) async {
        guard let service else { return }
        do {
            // Harvest won't set hours on a running timer, so when the time
            // changed: stop it, set the hours, and start it again.
            if entry.isRunning, let hours, abs(hours - entry.elapsed() / 3600) > 1.0 / 120 {
                let stopped = try await service.stopTimer(id: entry.id)
                let updated = try await service.updateEntry(
                    id: stopped.id, projectID: task.project.id, taskID: task.task.id, notes: notes, hours: hours
                )
                upsert(try await service.restartTimer(id: updated.id))
            } else {
                upsert(try await service.updateEntry(
                    id: entry.id, projectID: task.project.id, taskID: task.task.id,
                    notes: notes, hours: entry.isRunning ? nil : hours
                ))
            }
            errorMessage = nil
        } catch {
            await recover(from: error)
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
                notes: stopped.notes ?? "", hours: hours
            )
            if keepRunning { updated = try await service.restartTimer(id: updated.id) }
            upsert(updated)
            errorMessage = nil
        } catch {
            await recover(from: error)
        }
    }

    /// Adds an entry to `day`: a running timer when no hours are given (today
    /// only), otherwise a stopped entry with those hours.
    public func addEntry(task: TrackableTask, on day: LocalDate, notes: String, hours: Double?) async {
        guard let service, busyKey == nil else { return }
        busyKey = task.key
        defer { busyKey = nil }
        let notes = notes.isEmpty ? nil : notes
        do {
            if let hours {
                upsert(try await service.createEntry(projectID: task.project.id, taskID: task.task.id, spentDate: day, notes: notes, hours: hours))
            } else {
                if let current = running { upsert(try await service.stopTimer(id: current.id)) }
                upsert(try await service.startTimer(projectID: task.project.id, taskID: task.task.id, spentDate: day, notes: notes))
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteEntry(_ entry: TimeEntry) async {
        guard let service else { return }
        do {
            try await service.deleteEntry(id: entry.id)
            entries = entries.filter { $0.id != entry.id }
            lastDeleted = entry
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Puts the last deleted entry back: same task, day, notes and hours, and
    /// its timer running again if it was. Harvest gives it a new ID.
    public func undoDelete() async {
        guard let service, let entry = lastDeleted else { return }
        lastDeleted = nil
        do {
            var restored = try await service.createEntry(
                projectID: entry.project.id, taskID: entry.task.id, spentDate: entry.spentDate,
                notes: entry.notes, hours: entry.elapsed() / 3600
            )
            if entry.isRunning {
                if let current = running { upsert(try await service.stopTimer(id: current.id)) }
                restored = try await service.restartTimer(id: restored.id)
            }
            upsert(restored)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
        lastRefresh = nil
        phase = .signedOut
    }

    // MARK: Helpers

    private func upsert(_ entry: TimeEntry) {
        var updated = entries.filter { $0.id != entry.id }
        updated.append(entry)
        entries = Self.sorted(updated)
    }

    private static func sorted(_ entries: [TimeEntry]) -> [TimeEntry] {
        entries.sorted { ($0.spentDate, $0.updatedAt) > ($1.spentDate, $1.updatedAt) }
    }
}
