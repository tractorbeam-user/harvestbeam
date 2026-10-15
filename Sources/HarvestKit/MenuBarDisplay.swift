import Foundation

/// How much of the running task shows next to the menu bar icon. Stored in
/// UserDefaults so the settings menu and the status item agree.
public enum MenuBarDisplay {
    public enum Content: String, CaseIterable, Sendable {
        case timeOnly, task, taskAndProject, notes

        public var label: String {
            switch self {
            case .timeOnly: return "Time Only"
            case .task: return "Task"
            case .taskAndProject: return "Task and Project"
            case .notes: return "Notes (or Task)"
            }
        }
    }

    public enum Truncation: String, CaseIterable, Sendable {
        case end, middle

        public var label: String { self == .end ? "Cut Off the End" : "Cut Out the Middle" }
    }

    /// Character limits offered in settings; 0 means no limit.
    public static let lengths: [(label: String, value: Int)] = [
        ("Short (16)", 16), ("Medium (28)", 28), ("Long (44)", 44), ("No Limit", 0),
    ]

    public static let contentKey = "menuBar.content"
    public static let lengthKey = "menuBar.maxLength"
    public static let truncationKey = "menuBar.truncation"
    public static let showTimeKey = "menuBar.showTime"

    public static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            contentKey: Content.task.rawValue,
            lengthKey: 28,
            truncationKey: Truncation.end.rawValue,
            showTimeKey: true,
        ])
    }

    /// The text after the icon, e.g. "1:05  Design — Website Redesign".
    public static func title(
        task: TrackableTask, notes: String?, elapsed: TimeInterval, defaults: UserDefaults = .standard
    ) -> String {
        let content = Content(rawValue: defaults.string(forKey: contentKey) ?? "") ?? .task
        let limit = defaults.integer(forKey: lengthKey)
        let truncation = Truncation(rawValue: defaults.string(forKey: truncationKey) ?? "") ?? .end
        let showTime = defaults.bool(forKey: showTimeKey)

        let label: String
        switch content {
        case .timeOnly: label = ""
        case .task: label = task.task.name
        case .taskAndProject: label = "\(task.task.name) — \(task.project.name)"
        case .notes:
            let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            label = trimmed.isEmpty ? task.task.name : trimmed
        }
        let shortened = truncate(label, to: limit, style: truncation)
        let time = showTime || shortened.isEmpty ? TimeFormat.hoursMinutes(elapsed) : ""
        return [time, shortened].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    public static func truncate(_ text: String, to limit: Int, style: Truncation) -> String {
        guard limit > 1, text.count > limit else { return text }
        switch style {
        case .end:
            return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        case .middle:
            let head = (limit - 1) / 2 + (limit - 1) % 2
            let tail = (limit - 1) / 2
            return String(text.prefix(head)).trimmingCharacters(in: .whitespaces) + "…"
                + String(text.suffix(tail)).trimmingCharacters(in: .whitespaces)
        }
    }
}
