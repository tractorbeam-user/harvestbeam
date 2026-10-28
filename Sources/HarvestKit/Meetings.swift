import Foundation
import Observation

/// One meeting from your calendar, kept apart from EventKit so matching can be
/// tested and the demo can make some up.
public struct CalendarMeeting: Identifiable, Hashable, Sendable {
    /// Stable for this occurrence, even of a repeating meeting.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    /// When it was put on the calendar; a meeting added after it started
    /// isn't logged automatically, as in Toggl.
    public let createdAt: Date?
    /// A stretch of Timeline activity rather than a calendar event.
    public let isActivity: Bool
    /// For activity: the app and window most of it was in.
    public let context: ScreenContext?

    public init(id: String, title: String, start: Date, end: Date, createdAt: Date? = nil,
                isActivity: Bool = false, context: ScreenContext? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.createdAt = createdAt
        self.isActivity = isActivity
        self.context = context
    }

    public var hours: Double { max(0, end.timeIntervalSince(start)) / 3600 }
    public var day: LocalDate { LocalDate(start) }
}

/// The task a meeting probably belongs to, and why.
public struct MeetingSuggestion: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// You ticked "Always log this meeting here".
        case remembered
        /// An entry with this meeting's title as its notes.
        case loggedBefore(LocalDate)
        /// A project code in the title, like "[DAF]" or "PS-DM-01".
        case projectCode(String)
        /// A project's name in the title.
        case projectName(String)
        /// A client's name in the title.
        case clientName(String)
        /// One of your Autotracker rules, by the keyword that matched.
        case rule(String)
        /// You've tracked this task while in this app and window before.
        case trackedHere(String)
    }

    public let task: TrackableTask
    public let reason: Reason

    public var explanation: String {
        switch reason {
        case .remembered: "You always log this meeting here"
        case .loggedBefore: "You logged this meeting here before"
        case .projectCode(let code): "“\(code)” matches the project code"
        case .projectName(let name): "“\(name)” is in the title"
        case .clientName(let name): "“\(name)” is in the title"
        case .rule(let keyword): "Your rule for “\(keyword)”"
        case .trackedHere(let app): "You've tracked this in \(app) before"
        }
    }
}

/// Where a meeting stands in the week view.
public enum MeetingStatus: Hashable, Sendable {
    case logged
    case skipped
    /// Hasn't ended yet. You can still log it ahead of time; "log all"
    /// leaves it for later.
    case upcoming(MeetingSuggestion?)
    case matched(MeetingSuggestion)
    case unmatched
}

/// Picks a task for a meeting from its title.
public enum MeetingMatcher {
    /// Lowercased, accents folded, runs of spaces made one, for comparing
    /// titles with notes.
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Best guess first: what you told it to remember, then what you logged
    /// for this meeting before, then a project code, a project's name, and
    /// last a client's name.
    public static func suggestion(
        for title: String,
        tasks: [TrackableTask],
        entries: [TimeEntry],
        remembered: [String: TaskKey],
        usage: [TaskKey: Double]
    ) -> MeetingSuggestion? {
        let key = normalized(title)
        guard !key.isEmpty else { return nil }
        let byKey = Dictionary(tasks.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        if let saved = remembered[key], let task = byKey[saved] {
            return MeetingSuggestion(task: task, reason: .remembered)
        }
        // `entries` is newest first.
        if let entry = entries.first(where: { $0.notes.map(normalized) == key }), let task = byKey[entry.key] {
            return MeetingSuggestion(task: task, reason: .loggedBefore(entry.spentDate))
        }
        for code in codes(in: title) {
            let candidates = tasks.filter { task in
                guard let own = (task.projectCode ?? task.projectNameParts.code)?.uppercased() else { return false }
                return own == code || own.hasPrefix(code + "-")
            }
            if let task = mostUsed(candidates, usage: usage) {
                return MeetingSuggestion(task: task, reason: .projectCode(code))
            }
        }
        // The longest project name in the title. Short or generic names like
        // "Analytics" only count alongside their client's name. A name several
        // clients share ("Paid Search") needs the client's name too, or only
        // one of them in use; otherwise it's a guess, so make none.
        let named = Dictionary(grouping: tasks, by: \.project.id).values
            .compactMap { group -> (name: String, tasks: [TrackableTask], clientNamed: Bool)? in
                let name = group[0].projectNameParts.name
                let clientNamed = group[0].client.map { containsWords(normalized($0.name), in: key) } ?? false
                guard name.count >= 4, containsWords(normalized(name), in: key),
                      name.contains(" ") || clientNamed else { return nil }
                return (name, group, clientNamed)
            }
        if let longest = named.map({ normalized($0.name) }).max(by: { $0.count < $1.count }) {
            var best = named.filter { normalized($0.name) == longest }
            if best.count > 1, best.contains(where: \.clientNamed) { best = best.filter(\.clientNamed) }
            if best.count > 1 { best = best.filter { $0.tasks.contains { (usage[$0.key] ?? 0) > 0 } } }
            if best.count == 1, let task = mostUsed(best[0].tasks, usage: usage) {
                return MeetingSuggestion(task: task, reason: .projectName(best[0].name))
            }
        }
        // The longest client name in the title, so "Aston Bath Spa" beats "Aston Bath".
        var seen = Set<Int>()
        let clients = tasks.compactMap(\.client).filter { seen.insert($0.id).inserted }
            .filter { $0.name.count >= 3 && containsWords(normalized($0.name), in: key) }
            .sorted { $0.name.count > $1.name.count }
        for client in clients {
            let candidates = tasks.filter { $0.client?.id == client.id }
            if let task = mostUsed(candidates, usage: usage, requireUse: true) {
                return MeetingSuggestion(task: task, reason: .clientName(client.name))
            }
        }
        return nil
    }

    /// An entry on the meeting's day with its title as notes, leaving out
    /// entries another meeting already became (two "Design crit"s in a day
    /// are two entries, not one).
    public static func loggedEntry(for meeting: CalendarMeeting, in entries: [TimeEntry], claimed: Set<Int> = []) -> TimeEntry? {
        let key = normalized(meeting.title)
        let day = meeting.day
        return entries.first { $0.spentDate == day && !claimed.contains($0.id) && $0.notes.map(normalized) == key }
    }

    public static func isLogged(_ meeting: CalendarMeeting, in entries: [TimeEntry], claimed: Set<Int> = []) -> Bool {
        loggedEntry(for: meeting, in: entries, claimed: claimed) != nil
    }

    /// "[DAF] Review" → ["DAF"]; "PS-DM-01 sync" → ["PS-DM-01"]. Bracketed
    /// codes first, uppercased.
    static func codes(in title: String) -> [String] {
        var codes: [String] = []
        var rest = title[...]
        while let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
            let code = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces).uppercased()
            if !code.isEmpty, !code.contains(" ") { codes.append(code) }
            rest = rest[rest.index(after: close)...]
        }
        // Bare codes look like LETTERS-LETTERS-01.
        for word in title.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" }) {
            let parts = word.split(separator: "-")
            if parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }), parts.contains(where: { $0.allSatisfy(\.isNumber) }),
               parts.first!.allSatisfy(\.isLetter) {
                let code = word.uppercased()
                if !codes.contains(code) { codes.append(code) }
            }
        }
        return codes
    }

    /// The task you use most; ties go to the first by project then task name.
    /// With `requireUse`, nil unless you've used one, or one is for meetings.
    private static func mostUsed(_ tasks: [TrackableTask], usage: [TaskKey: Double], requireUse: Bool = false) -> TrackableTask? {
        let ordered = tasks.sorted { ($0.project.name, $0.task.name) < ($1.project.name, $1.task.name) }
        if let used = ordered.max(by: { (usage[$0.key] ?? 0) < (usage[$1.key] ?? 0) }), (usage[used.key] ?? 0) > 0 {
            return used
        }
        if requireUse {
            return ordered.first { normalized($0.task.name).contains("meeting") }
        }
        return ordered.first
    }

    private static func containsWords(_ phrase: String, in text: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: phrase, range: searchRange) {
            let before = found.lowerBound == text.startIndex || !text[text.index(before: found.lowerBound)].isLetter
            let after = found.upperBound == text.endIndex || !text[found.upperBound].isLetter
            if before && after { return true }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }
}

/// What you've done with meetings: logged (and as which entry), skipped, and
/// the ones you always log to the same task. Kept in preferences on this Mac.
@MainActor @Observable
public final class MeetingMemory {
    public private(set) var remembered: [String: TaskKey]
    /// Meeting ID → the entry it became.
    public private(set) var logged: [String: Int]
    public private(set) var skipped: Set<String>

    @ObservationIgnored private let defaults: UserDefaults
    private static let rememberedKey = "meetings.remembered.v1"
    private static let loggedKey = "meetings.logged.v1"
    private static let skippedKey = "meetings.skipped.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.dictionary(forKey: Self.rememberedKey) as? [String: String] ?? [:]
        remembered = saved.compactMapValues(TaskKey.init)
        logged = defaults.dictionary(forKey: Self.loggedKey) as? [String: Int] ?? [:]
        skipped = Set(defaults.stringArray(forKey: Self.skippedKey) ?? [])
    }

    public func remember(_ title: String, as key: TaskKey) {
        remembered[MeetingMatcher.normalized(title)] = key
        defaults.set(remembered.mapValues(\.description), forKey: Self.rememberedKey)
    }

    public func forget(_ title: String) {
        remembered[MeetingMatcher.normalized(title)] = nil
        defaults.set(remembered.mapValues(\.description), forKey: Self.rememberedKey)
    }

    public func markLogged(_ meetingID: String, entryID: Int) {
        logged[meetingID] = entryID
        skipped.remove(meetingID)
        save()
    }

    public func setSkipped(_ meetingID: String, _ isSkipped: Bool) {
        if isSkipped { skipped.insert(meetingID) } else { skipped.remove(meetingID) }
        save()
    }

    /// Saves, dropping meetings from more than four months ago: they're past
    /// any history the app shows. IDs end in "@<start, Unix seconds>".
    private func save() {
        let cutoff = Date().addingTimeInterval(-120 * 86_400).timeIntervalSince1970
        func isRecent(_ id: String) -> Bool {
            guard let at = id.split(separator: "@").last.flatMap({ Double($0) }), id.contains("@") else { return true }
            return at >= cutoff
        }
        logged = logged.filter { isRecent($0.key) }
        skipped = skipped.filter(isRecent)
        defaults.set(logged, forKey: Self.loggedKey)
        defaults.set(Array(skipped), forKey: Self.skippedKey)
    }
}

extension TimeTracker {
    public func meetingSuggestion(for meeting: CalendarMeeting) -> MeetingSuggestion? {
        // Activity: what you ticked "always" for, then the screen's clues.
        if let context = meeting.context {
            if let saved = meetingMemory.remembered[MeetingMatcher.normalized(meeting.title)],
               let task = tasks(for: [saved]).first {
                return MeetingSuggestion(task: task, reason: .remembered)
            }
            return suggestion(for: context)
        }
        return MeetingMatcher.suggestion(
            for: meeting.title, tasks: tasks, entries: entries,
            remembered: meetingMemory.remembered, usage: usage
        )
    }

    public func status(of meeting: CalendarMeeting, at now: Date = .now) -> MeetingStatus {
        if entry(for: meeting) != nil { return .logged }
        if meetingMemory.skipped.contains(meeting.id) { return .skipped }
        if meeting.end > now { return .upcoming(meetingSuggestion(for: meeting)) }
        return meetingSuggestion(for: meeting).map(MeetingStatus.matched) ?? .unmatched
    }

    /// The entry a meeting became, if it's still there.
    public func entry(for meeting: CalendarMeeting) -> TimeEntry? {
        if let entryID = meetingMemory.logged[meeting.id], let entry = entries.first(where: { $0.id == entryID }) {
            return entry
        }
        // Entries other meetings became aren't this one's.
        let claimed = Set(meetingMemory.logged.filter { $0.key != meeting.id }.values)
        return MeetingMatcher.loggedEntry(for: meeting, in: entries, claimed: claimed)
    }

    /// Adds the meeting as a stopped entry on its day. `remember` makes this
    /// task the suggestion for every meeting with the same title; without it,
    /// any earlier "always" for that title is dropped.
    public func log(_ meeting: CalendarMeeting, task: TrackableTask, notes: String, hours: Double, remember: Bool) async {
        if remember {
            meetingMemory.remember(meeting.title, as: task.key)
        } else {
            meetingMemory.forget(meeting.title)
        }
        if let entry = await addEntry(task: task, on: meeting.day, notes: notes, hours: hours, startingAt: meeting.start) {
            meetingMemory.markLogged(meeting.id, entryID: entry.id)
        }
    }

    /// Logs each meeting to its suggested task, one after another.
    public func logSuggested(_ meetings: [CalendarMeeting]) async {
        for meeting in meetings {
            guard case .matched(let suggestion) = status(of: meeting) else { continue }
            await log(meeting, task: suggestion.task, notes: meeting.title, hours: meeting.hours,
                      remember: suggestion.reason == .remembered)
        }
    }

    public func setSkipped(_ meeting: CalendarMeeting, _ isSkipped: Bool) {
        meetingMemory.setSkipped(meeting.id, isSkipped)
    }
}
