#if os(macOS)
import EventKit
import Foundation
import HarvestKit
import Observation

/// Meetings from the calendars on this Mac (whatever Calendar.app shows:
/// iCloud, Google, Exchange). Read only; nothing leaves the Mac.
@MainActor @Observable
public final class CalendarStore {
    public enum Access: Equatable {
        case notAsked, granted, denied
        /// Running outside an app bundle, where macOS can't ask.
        case unavailable
    }

    public private(set) var access: Access = .notAsked
    /// Bumped when the calendars change, so views reload their meetings.
    public private(set) var revision = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let demoMeetings: [CalendarMeeting]?
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// The last week asked for, until the calendars change.
    @ObservationIgnored private var cached: (from: LocalDate, through: LocalDate, revision: Int, meetings: [CalendarMeeting])?

    public init() {
        demoMeetings = nil
        refreshAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision += 1 }
        }
    }

    /// Made-up meetings around today, for `--demo` and snapshots.
    public init(demoMeetings: [CalendarMeeting]) {
        self.demoMeetings = demoMeetings
        access = .granted
    }

    public var isDemo: Bool { demoMeetings != nil }

    /// Picks up access turned on or off in System Settings since launch.
    public func recheckAccess() {
        guard demoMeetings == nil else { return }
        let before = access
        refreshAccess()
        if access != before { revision += 1 }
    }

    private func refreshAccess() {
        guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else {
            access = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .notAsked
        default: access = .denied
        }
    }

    public func requestAccess() async {
        guard access == .notAsked else { return }
        _ = try? await store.requestFullAccessToEvents()
        refreshAccess()
        revision += 1
    }

    /// Timed meetings that start on `from` through `through`, earliest first.
    /// Leaves out all-day events, cancelled ones and ones you declined.
    public func meetings(from: LocalDate, through: LocalDate) -> [CalendarMeeting] {
        if let demoMeetings {
            return demoMeetings.filter { $0.day >= from && $0.day <= through }.sorted { $0.start < $1.start }
        }
        guard access == .granted else { return [] }
        if let cached, cached.from == from, cached.through == through, cached.revision == revision {
            return cached.meetings
        }
        let predicate = store.predicateForEvents(withStart: from.date(), end: through.adding(days: 1).date(), calendars: nil)
        let meetings = store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.status != .canceled else { return false }
                let length = event.endDate.timeIntervalSince(event.startDate)
                guard length >= 5 * 60, length <= 10 * 3600 else { return false }
                let me = event.attendees?.first(where: \.isCurrentUser)
                return me?.participantStatus != .declined
            }
            .map { event in
                CalendarMeeting(
                    // The external identifier survives a full calendar resync;
                    // a repeating meeting shares it across occurrences, so the
                    // start tells them apart.
                    id: "\(event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier)@\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? "Untitled meeting",
                    start: event.startDate, end: event.endDate, createdAt: event.creationDate
                )
            }
            .sorted { $0.start < $1.start }
        cached = (from, through, revision, meetings)
        return meetings
    }

    /// A believable week of meetings for the demo account.
    public static func demo(now: Date = .now) -> CalendarStore {
        let monday = LocalDate(now).startOfWeek(firstWeekday: 2)
        func meeting(_ day: Int, _ hour: Double, _ minutes: Double, _ title: String) -> CalendarMeeting {
            let start = monday.adding(days: day).date().addingTimeInterval(hour * 3600)
            return CalendarMeeting(id: "demo-\(day)-\(hour)", title: title, start: start, end: start.addingTimeInterval(minutes * 60))
        }
        return CalendarStore(demoMeetings: [
            meeting(0, 9.5, 30, "Website Redesign standup"),
            meeting(0, 11, 60, "Acme Co brand review"),
            meeting(0, 14, 90, "[TB-CTX] Launch planning"),
            meeting(0, 16.5, 30, "Lunch with Sam"),
            meeting(1, 9.5, 30, "Website Redesign standup"),
            meeting(1, 13, 60, "Northwind data sync"),
            meeting(2, 9.5, 30, "Website Redesign standup"),
            meeting(2, 10, 45, "Design crit"),
            meeting(2, 15, 30, "Acme Co mobile app check-in"),
            meeting(3, 9.5, 30, "Website Redesign standup"),
            meeting(3, 11, 90, "Tractors Who Train Together | Session 1B"),
            meeting(4, 9.5, 30, "Website Redesign standup"),
            meeting(4, 15, 60, "Northwind quarterly review"),
        ])
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
#endif
