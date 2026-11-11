import Foundation

/// One change to time that can be put back, written as what to do to put it
/// back. Applying one returns its own opposite, which is how redo works.
enum UndoOp: Sendable {
    /// Delete an entry this session made.
    case delete(entryID: Int)
    /// Make a deleted entry again: same task, day, notes and time, its
    /// timer running again if it was. Harvest gives it a new ID.
    case recreate(TimeEntry)
    /// Put an entry's task, notes, time and running state back as they were.
    case revert(TimeEntry)
    /// Stop a timer that was started; delete it too when it was new and has
    /// under a minute on it.
    case stop(entryID: Int, deleteIfShort: Bool)
    /// Start a paused timer again.
    case restart(entryID: Int)
    /// Favorites, in this order.
    case favorites([TaskKey])
    /// Several at once, in order; undone in reverse.
    case group([UndoOp])
}

/// A change in the undo or redo list, with the words for it.
struct UndoStep: Sendable {
    let label: String
    let op: UndoOp
}

/// The little "Moved 0:20 to Dallas Art Fair · Undo" note after a change.
public struct UndoToast: Equatable, Identifiable, Sendable {
    public enum Action: Sendable { case undo, redo }
    public let id: Int
    public let message: String
    /// The button it offers: Undo after a change or a redo, Redo after an undo.
    public let action: Action
}

/// Why an undo couldn't happen, in words.
struct UndoFailure: Error {
    let reason: String

    static let gone = UndoFailure(reason: "that entry isn't in Harvest any more.")
    static func locked(_ lock: EntryLock) -> UndoFailure {
        UndoFailure(reason: "the entry is \(lock.title.lowercased()) now. " + lock.detail)
    }
}

extension TimeTracker {
    /// How many changes undo remembers.
    static let undoLimit = 20

    public var canUndo: Bool { !undoStack.isEmpty && !isUndoing }
    public var canRedo: Bool { !redoStack.isEmpty && !isUndoing }
    /// What ⌘Z would undo, for the Edit menu ("Moved 0:20 to …").
    public var undoLabel: String? { undoStack.last?.label }
    public var redoLabel: String? { redoStack.last?.label }

    /// Puts back the most recent change. If Harvest won't have it (the entry
    /// was locked or deleted meanwhile), says so and forgets that change.
    public func undo() async {
        guard let step = undoStack.last, !isUndoing else { return }
        undoStack.removeLast()
        if let inverse = await run(step, verb: "undo") {
            redoStack.append(UndoStep(label: step.label, op: inverse))
            showToast("Undone: " + step.label, action: .redo)
        }
    }

    /// Makes the most recently undone change again.
    public func redo() async {
        guard let step = redoStack.last, !isUndoing else { return }
        redoStack.removeLast()
        if let inverse = await run(step, verb: "redo") {
            undoStack.append(UndoStep(label: step.label, op: inverse))
            trimUndo()
            showToast(step.label, action: .undo)
        }
    }

    public func dismissToast() { toast = nil }

    /// Forgets every change, for sign-out or a fresh start.
    public func clearUndoHistory() {
        undoStack = []
        redoStack = []
        idAliases = [:]
        toast = nil
    }

    // MARK: Recording

    /// Remembers a change made just now, unless it's part of a bigger one
    /// being recorded as a whole.
    func record(_ label: String, _ op: UndoOp) {
        guard recordingPaused == 0 else { return }
        undoStack.append(UndoStep(label: label, op: op))
        trimUndo()
        redoStack = []
        showToast(label, action: .undo)
    }

    /// Runs `body` without recording its changes on their own.
    func withoutRecording<T>(_ body: () async -> T) async -> T {
        recordingPaused += 1
        defer { recordingPaused -= 1 }
        return await body()
    }

    func favoritesChanged(from before: [TaskKey], to after: [TaskKey]) {
        let label: String
        if let added = after.first(where: { !before.contains($0) }), after.count > before.count {
            label = "Added \(shortName(for: added)) to Favorites"
        } else if let removed = before.first(where: { !after.contains($0) }), after.count < before.count {
            label = "Removed \(shortName(for: removed)) from Favorites"
        } else {
            label = "Reordered Favorites"
        }
        record(label, .favorites(before))
    }

    func shortName(for key: TaskKey) -> String {
        favoriteTasks.first { $0.key == key }.map(shortName(for:))
            ?? tasks(for: [key]).first.map(shortName(for:))
            ?? "a task"
    }

    func shortName(for task: TrackableTask) -> String { task.projectNameParts.name }

    func shortName(for entry: TimeEntry) -> String { shortName(for: task(for: entry)) }

    /// What undoing a start does: stop the new timer (deleting it if it had
    /// barely begun), and start again the one it stopped.
    func startOp(started: TimeEntry, wasNew: Bool, stopped: TimeEntry?) -> UndoOp {
        let stop = UndoOp.stop(entryID: started.id, deleteIfShort: wasNew)
        guard let stopped, stopped.id != started.id else { return stop }
        return .group([stop, .restart(entryID: stopped.id)])
    }

    // MARK: Applying

    private func trimUndo() {
        if undoStack.count > Self.undoLimit { undoStack.removeFirst(undoStack.count - Self.undoLimit) }
    }

    private func showToast(_ message: String, action: UndoToast.Action) {
        toastCounter += 1
        toast = UndoToast(id: toastCounter, message: message, action: action)
    }

    /// Applies a step, returning its opposite, or nil (with the reason
    /// shown) when Harvest wouldn't have it.
    private func run(_ step: UndoStep, verb: String) async -> UndoOp? {
        isUndoing = true
        defer { isUndoing = false }
        do {
            let inverse = try await apply(step.op)
            errorMessage = nil
            return inverse
        } catch {
            toast = nil
            let reason: String
            switch error {
            case let failure as UndoFailure: reason = failure.reason
            case HarvestError.server(404, _): reason = UndoFailure.gone.reason
            case HarvestError.server(_, let message?): reason = "Harvest said: \(message)."
            default: reason = error.localizedDescription
            }
            errorMessage = "Couldn't \(verb) “\(step.label)”: " + reason
            // Whatever changed meanwhile, show Harvest as it is now.
            if error is HarvestError {
                let message = errorMessage
                await refresh(force: true)
                errorMessage = message
            }
            return nil
        }
    }

    /// Follows an entry through being deleted and made again, which gives
    /// it a new ID.
    private func resolve(_ id: Int) -> Int {
        var id = id
        var hops = 0
        while let next = idAliases[id], hops < 50 { id = next; hops += 1 }
        return id
    }

    private func current(_ id: Int) throws -> TimeEntry {
        guard let entry = entries.first(where: { $0.id == resolve(id) }) else { throw UndoFailure.gone }
        return entry
    }

    private func editable(_ id: Int) throws -> TimeEntry {
        let entry = try current(id)
        if let lock = entry.lock { throw UndoFailure.locked(lock) }
        return entry
    }

    private func stopOtherTimer(than id: Int, using service: any HarvestService) async throws {
        if let other = running, other.id != id { upsert(try await service.stopTimer(id: other.id)) }
    }

    private func apply(_ op: UndoOp) async throws -> UndoOp {
        guard let service else { throw UndoFailure(reason: "you're signed out.") }
        switch op {
        case .delete(let id):
            let entry = try editable(id)
            try await service.deleteEntry(id: entry.id)
            removeEntry(id: entry.id)
            return .recreate(entry)

        case .recreate(let entry):
            let hours = entry.elapsed() / 3600
            var restored = try await service.createEntry(
                projectID: entry.project.id, taskID: entry.task.id, spentDate: entry.spentDate,
                notes: entry.notes, hours: hours, times: times(for: entry, hours: hours)
            )
            if entry.isRunning {
                try await stopOtherTimer(than: restored.id, using: service)
                restored = try await service.restartTimer(id: restored.id)
            }
            upsert(restored)
            idAliases[entry.id] = restored.id
            return .delete(entryID: restored.id)

        case .revert(let target):
            let now = try editable(target.id)
            let hours = target.elapsed() / 3600
            var updated: TimeEntry
            if now.isRunning, target.isRunning, abs(now.elapsed() - target.elapsed()) < 60 {
                // Just the task or notes; the timer carries on.
                updated = try await service.updateEntry(
                    id: now.id, projectID: target.project.id, taskID: target.task.id,
                    notes: target.notes ?? "", hours: nil, times: nil
                )
            } else {
                // Harvest won't set hours on a running timer: stop, set, restart.
                updated = now.isRunning ? try await service.stopTimer(id: now.id) : now
                updated = try await service.updateEntry(
                    id: updated.id, projectID: target.project.id, taskID: target.task.id,
                    notes: target.notes ?? "", hours: hours, times: times(for: updated, hours: hours)
                )
                if target.isRunning {
                    try await stopOtherTimer(than: updated.id, using: service)
                    updated = try await service.restartTimer(id: updated.id)
                }
            }
            upsert(updated)
            return .revert(now)

        case .stop(let id, let deleteIfShort):
            let now = try current(id)
            if deleteIfShort, now.elapsed() < 60, now.lock == nil {
                try await service.deleteEntry(id: now.id)
                removeEntry(id: now.id)
                return .recreate(now)
            }
            if now.isRunning { upsert(try await service.stopTimer(id: now.id)) }
            return .restart(entryID: now.id)

        case .restart(let id):
            let now = try editable(id)
            if !now.isRunning {
                try await stopOtherTimer(than: now.id, using: service)
                upsert(try await service.restartTimer(id: now.id))
            }
            return .stop(entryID: now.id, deleteIfShort: false)

        case .favorites(let keys):
            let before = favorites.keys
            favorites.replace(with: keys)
            return .favorites(before)

        case .group(let ops):
            var inverses: [UndoOp] = []
            do {
                for op in ops { inverses.append(try await apply(op)) }
            } catch {
                // Don't leave it half done: put back what already changed.
                for inverse in inverses.reversed() { _ = try? await apply(inverse) }
                throw error
            }
            return .group(inverses.reversed())
        }
    }
}
