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
    public private(set) var tasks: [TrackableTask] = []
    /// The last `historyDays` of the user's time entries, newest first.
    public private(set) var entries: [TimeEntry] = []
    public private(set) var isRefreshing = false
    /// The task whose start/stop request is in flight.
    public private(set) var busyKey: TaskKey?
    public var errorMessage: String?
    /// Bumped whenever the panel opens so the search field can grab focus.
    public private(set) var focusRequest = 0

    public let favorites: FavoritesStore
    public let isDemo: Bool

    @ObservationIgnored private var service: (any HarvestService)?
    @ObservationIgnored private var lastRefresh: Date?
    @ObservationIgnored private var tasksByKey: [TaskKey: TrackableTask] = [:]

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
        todayEntries.reduce(0) { $0 + $1.elapsed(at: now) }
    }

    public var favoriteTasks: [TrackableTask] {
        favorites.keys.compactMap { tasksByKey[$0] }
    }

    public var recentTasks: [TrackableTask] {
        Ranking.recent(from: entries, excluding: favorites.set, limit: 4).compactMap { tasksByKey[$0] }
    }

    public var suggestedTasks: [TrackableTask] {
        let shown = favorites.set.union(recentTasks.map(\.key))
        let assignable = entries.filter { tasksByKey[$0.key] != nil }
        return Ranking.suggested(from: assignable, excluding: shown, limit: 4).compactMap { tasksByKey[$0] }
    }

    public func search(_ query: String) -> [TrackableTask] {
        Ranking.search(query, in: tasks, usage: Ranking.usageScores(from: entries), favorites: favorites.set)
    }

    public var harvestWebURL: URL? {
        guard let base = company?.baseUri else { return URL(string: "https://id.getharvest.com") }
        return URL(string: base + "/time")
    }

    // MARK: Lifecycle

    /// Call when the panel or app comes to the front.
    public func didAppear() {
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
            async let assignments = service.projectAssignments()
            async let history = service.timeEntries(userID: me.id, from: today.adding(days: -Self.historyDays), to: today)
            let (loadedAssignments, loadedEntries) = try await (assignments, history)

            tasks = ProjectAssignment.trackableTasks(from: loadedAssignments)
            tasksByKey = Dictionary(tasks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            entries = Self.sorted(loadedEntries)
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

    /// Starts tracking `task`, or stops it if it's the one already running.
    /// Reuses today's entry for the same task, like Harvest's own timer does.
    public func toggle(_ task: TrackableTask) async {
        if running?.key == task.key {
            await stop()
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
            errorMessage = error.localizedDescription
        }
    }

    public func stop() async {
        guard let service, let current = running, busyKey == nil else { return }
        busyKey = current.key
        defer { busyKey = nil }
        do {
            upsert(try await service.stopTimer(id: current.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
        tasksByKey = [:]
        entries = []
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
