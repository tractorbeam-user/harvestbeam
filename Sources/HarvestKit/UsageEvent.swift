/// The milestones counted for Harvestbeam's anonymous usage stats. Each is
/// only a name: nothing about your projects, clients, entries or account.
public enum UsageEvent: String, Sendable {
    case signedIn = "Account.signedIn"
    case timerStarted = "Timer.started"
    case weekCalendarOpened = "WeekCalendar.opened"
}
