import Foundation

/// Answers to "how do I…" questions typed into the ask box. Matched by
/// keywords on this Mac; nothing is sent anywhere.
public struct HelpTopic: Identifiable, Equatable, Sendable {
    public let id: String
    public let question: String
    public let answer: String
    let keywords: [String]
}

public enum AppHelp {
    /// Whether ask-box text is a question about the app rather than a
    /// search, a command or a description of the day.
    public static func isQuestion(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.split(separator: " ").count >= 2 || lower == "help" else { return lower == "help" }
        if lower.hasSuffix("?") { return true }
        let openers = ["how ", "how's ", "where ", "what's ", "what is ", "what does ", "can i ", "can you ", "is there ",
                       "why ", "help", "where's ", "which ", "do i ", "does it ", "is it "]
        return openers.contains(where: lower.hasPrefix)
    }

    /// The best answers for a question, best first; empty when nothing fits.
    public static func answers(for text: String, limit: Int = 2) -> [HelpTopic] {
        // "help" on its own: the basics, to show what can be asked.
        if text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) == "help" {
            return topics.filter { ["start", "add", "sentence", "move", "edit", "undo"].contains($0.id) }
        }
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }
        guard !words.isEmpty else { return [] }
        func matches(_ topic: HelpTopic, _ word: String) -> Bool {
            topic.keywords.contains { $0.hasPrefix(String(word.prefix(4))) || word.hasPrefix($0) }
        }
        // A word few topics share ("split") counts for more than a common one ("entry").
        let scored = topics.map { topic -> (HelpTopic, Double) in
            let score = words.reduce(0.0) { total, word in
                guard matches(topic, word) else { return total }
                let inTitle = topic.question.lowercased().contains(word) ? 0.5 : 0
                return total + 1 / Double(topics.filter { matches($0, word) }.count) + inTitle
            }
            return (topic, score)
        }
        let best = scored.map(\.1).max() ?? 0
        guard best > 0 else { return [] }
        return scored.filter { $0.1 >= best * 0.75 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private static let stopWords: Set<String> = [
        "how", "the", "can", "and", "for", "you", "does", "what", "where", "why", "this", "that", "with", "into",
        "from", "make", "use", "get", "want", "there", "some", "any", "app", "harvestbeam", "do", "is", "my", "an",
    ]

    static let topics: [HelpTopic] = [
        .init(id: "start", question: "Start a timer",
              answer: "Click any tile, or type a project, client or code here and press Return. Clicking the running one pauses it.",
              keywords: ["start", "timer", "track", "begin", "play"]),
        .init(id: "add", question: "Add time without a timer",
              answer: "Type how long and what, like \"30m on Website\", and press Return. Or press ⌘N for a new entry.",
              keywords: ["add", "log", "manual", "entry", "past", "minutes", "hours", "new"]),
        .init(id: "sentence", question: "Turn a sentence into entries",
              answer: "Describe your day here, like \"I worked on Context all morning and had a call with Dallas Art Fair\", then press Return. You check the entries before they're added. ⌘P opens the same planner.",
              keywords: ["sentence", "describe", "plan", "day", "dictate", "voice", "speak", "talk"]),
        .init(id: "move", question: "Move time between tasks",
              answer: "Type \"move 20m from Admin to Website\" and press Return. Or right-click an entry › Split Entry… to send part of it elsewhere.",
              keywords: ["move", "shift", "transfer", "swap", "reassign", "wrong"]),
        .init(id: "split", question: "Split an entry",
              answer: "Right-click the entry › Split Entry…, pick how much and where it goes. A running timer keeps running with what's left.",
              keywords: ["split", "divide", "part", "portion", "separate"]),
        .init(id: "merge", question: "Merge entries for the same task",
              answer: "Right-click one of them › Merge … Entries. The time adds up into one entry, with every note kept. ⌘Z undoes it.",
              keywords: ["merge", "combine", "duplicate", "same", "join", "multiple"]),
        .init(id: "edit", question: "Change an entry's time or notes",
              answer: "Double-click the entry, or right-click › Edit Entry. Here you can also type \"make Website 1:30\" or \"note: client feedback\".",
              keywords: ["edit", "change", "fix", "hours", "notes", "note", "adjust", "correct"]),
        .init(id: "undo", question: "Undo a change",
              answer: "Press ⌘Z, or click Undo on the note that appears after a change. ⇧⌘Z redoes it.",
              keywords: ["undo", "mistake", "revert", "back", "redo", "oops"]),
        .init(id: "delete", question: "Delete an entry",
              answer: "Right-click the entry › Delete Entry. ⌘Z brings it back.",
              keywords: ["delete", "remove", "trash", "erase"]),
        .init(id: "stop", question: "Stop or pause the timer",
              answer: "Click the running tile or its pause button, press ⌘., or type \"stop\" here.",
              keywords: ["stop", "pause", "end", "finish"]),
        .init(id: "favorites", question: "Add and order favorites",
              answer: "Drag a tile into Favorites, click its star, or right-click › Add to Favorites. Drag favorites onto each other to reorder them.",
              keywords: ["favorite", "favourite", "star", "pin", "reorder", "order"]),
        .init(id: "sections", question: "Arrange Favorites, Recent and Suggested",
              answer: "Drag a section's title to move it, or use the ⋯ on its title › Move Up or Move Down. Half Width there puts two sections side by side; One Tile per Row stacks a section's tiles in a single column.",
              keywords: ["section", "sections", "group", "groups", "arrange", "layout", "recent", "suggested", "column", "columns", "dashboard", "width", "side", "organize", "row", "single", "one"]),
        .init(id: "reorder", question: "Reorder Recent or Suggested",
              answer: "Drag a tile onto another in the same section to move it there. Your order is remembered.",
              keywords: ["reorder", "order", "sort", "arrange", "recent", "suggested", "drag"]),
        .init(id: "guide", question: "What a time-tracking code is for",
              answer: "Click the book at the bottom of the window for the Time Tracking Guide: each Digital Products code and what goes in it. Type in it to filter.",
              keywords: ["guide", "code", "codes", "glossary", "bucket", "buckets", "meaning", "mean", "which", "digital"]),
        .init(id: "web", question: "Open Harvest on the web",
              answer: "Click the arrow-in-a-box button at the bottom right of the window. Right-click an entry › View in Harvest opens that day.",
              keywords: ["web", "website", "browser", "online", "globe", "site", "open"]),
        .init(id: "summary", question: "See where the week went",
              answer: "Click the week total in the title bar for the Weekly Summary. Rest the pointer on it for today, yesterday, this week and this month.",
              keywords: ["week", "summary", "total", "report", "month", "share", "image", "where"]),
        .init(id: "review", question: "Check the week before it closes",
              answer: "The gear at the bottom › Review Week… lists short days, gaps, missing notes and retired buckets. It also opens from the Friday reminder.",
              keywords: ["review", "friday", "gaps", "missing", "close", "timesheet", "check"]),
        .init(id: "appearance", question: "Dark mode",
              answer: "Settings › General › Appearance: System, Light or Dark. It's also in the gear menu at the bottom.",
              keywords: ["dark", "light", "appearance", "theme", "mode", "color"]),
        .init(id: "menubar", question: "Change what the menu bar shows",
              answer: "Settings › General › Menu Bar: the task, the project or just the time, and how long it can be.",
              keywords: ["menu", "bar", "status", "icon", "show", "length"]),
        .init(id: "ontop", question: "Keep the window on top",
              answer: "Settings › General › Keep the window on top, or the gear at the bottom › Keep on Top.",
              keywords: ["top", "float", "above", "window", "pin"]),
        .init(id: "shortcut", question: "Open Harvestbeam from the keyboard",
              answer: "⌥H (unless you changed it) shows or hides it from anywhere. Change it in Settings › Shortcuts.",
              keywords: ["shortcut", "keyboard", "hotkey", "key", "open", "hide", "keys"]),
        .init(id: "labs", question: "Try beta features",
              answer: "Settings › Labs turns on automatic tracking, auto-logged meetings or the start/pause shortcut, one at a time.",
              keywords: ["beta", "labs", "experimental", "automatic", "autotrack", "feature"]),
        .init(id: "rules", question: "Start timers automatically with rules",
              answer: "Turn on Labs › Automatic tracking, then Settings › Tracking › Track with rules and Add Rule…. Window titles need Accessibility access.",
              keywords: ["rule", "rules", "automatic", "autotrack", "keyword", "detect", "figma", "browser"]),
        .init(id: "idle", question: "Handle time I was away",
              answer: "With Detect idle time on (Settings › General), coming back to a running timer asks whether to keep the time you were away.",
              keywords: ["idle", "away", "afk", "inactive", "break", "lunch"]),
        .init(id: "reminders", question: "Get reminders",
              answer: "Settings › General › Reminders: nothing tracked by a set time, a timer running long, and the Friday week review.",
              keywords: ["remind", "reminder", "notification", "notify", "alert", "forget"]),
        .init(id: "locked", question: "Why can't I change an entry?",
              answer: "It's approved, invoiced or in a closed week, or its project is archived. Right-click it › Why Is This …? for details.",
              keywords: ["locked", "lock", "approved", "invoiced", "archived", "cant", "can't", "grey", "gray"]),
        .init(id: "feedback", question: "Send feedback or report a bug",
              answer: "Click the speech bubble at the bottom of the window to send a bug, a question or an idea.",
              keywords: ["feedback", "bug", "report", "idea", "suggest", "contact", "support"]),
        .init(id: "signout", question: "Sign out or switch accounts",
              answer: "The gear at the bottom › Sign Out, then sign in with another Harvest token.",
              keywords: ["sign", "logout", "log", "account", "switch", "token"]),
    ]
}
