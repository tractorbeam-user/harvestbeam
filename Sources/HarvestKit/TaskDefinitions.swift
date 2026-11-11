import Foundation

/// What a bucket in the team's time-tracking policy is for: "[TB-DP-12]
/// Billing: drafting and sending invoices…". Matched to tasks by the code in
/// the project's name or code, or by name for the buckets without one.
public struct TaskDefinition: Hashable, Sendable {
    /// "TB-DP-12"; nil for PTO, Cross-Divisional and the retired buckets.
    public let code: String?
    /// "Billing"
    public let name: String
    /// What goes here, as the policy words it.
    public let summary: String
    /// For a retired bucket, where its time goes now.
    public let replacement: String?

    public var isRetired: Bool { replacement != nil }

    /// "[TB-DP-12] Billing", or just the name.
    public var title: String { code.map { "[\($0)] \(name)" } ?? name }

    /// The gray line under a task in search, or its tooltip.
    public var detail: String {
        if let replacement { return "Retired: \(replacement)" }
        return summary
    }

    public init(code: String?, name: String, summary: String, replacement: String? = nil) {
        self.code = code
        self.name = name
        self.summary = summary
        self.replacement = replacement
    }
}

public enum TaskDefinitions {
    /// The policy's codes as written.
    public static let all: [TaskDefinition] = [
        TaskDefinition(code: "TB-DP-01", name: "Admin",
                       summary: "General administrative overhead, Wrike setup and adjustments, reading and responding to general emails."),
        TaskDefinition(code: "TB-DP-12", name: "Billing",
                       summary: "Drafting and sending invoices, reviewing and approving vendor or contractor invoices."),
        TaskDefinition(code: "TB-DP-13", name: "Process Development",
                       summary: "Internal workflow improvements, creating SOPs, documentation, designing operational tools (time tracking systems, project templates)."),
        TaskDefinition(code: "TB-DP-14", name: "Hiring",
                       summary: "Job descriptions, screening portfolios and resumes, candidate interviews, debriefing."),
        TaskDefinition(code: "TB-DP-15", name: "Meetings (Non-Client)",
                       summary: "Internal one-on-ones, team retrospectives, department syncs, company-wide All-Hands."),
        TaskDefinition(code: "TB-DP-18", name: "Research & Self-Education",
                       summary: "Skill development, exploring new tools or technologies, software workflow training not tied to a client contract."),
        TaskDefinition(code: "TB-DP-19", name: "Business Dev",
                       summary: "Pre-sale activities, prospective client discovery calls, internal proposal alignment, pitch deck creation, technical site audits, solution scoping."),
        pto,
        crossDivisional,
        retiredDigitalProducts,
        retiredBusinessDev,
    ]

    static let pto = TaskDefinition(code: nil, name: "PTO",
                                    summary: "Holidays, vacation, sick leave, doctor and medical appointments.")
    static let crossDivisional = TaskDefinition(
        code: nil, name: "Cross-Divisional Processes, Training, & Development",
        summary: "Organization-wide initiatives, cross-functional committees, company-wide training.")
    static let retiredDigitalProducts = TaskDefinition(
        code: nil, name: "Digital Products", summary: "The old catch-all Digital Products bucket.",
        replacement: "use a specific [TB-DP-xx] code, or [TB-DP-01] Admin.")
    static let retiredBusinessDev = TaskDefinition(
        code: nil, name: "Business Dev", summary: "The old Business Dev bucket.",
        replacement: "use [TB-DP-19] Business Dev.")

    private static let byCode = Dictionary(uniqueKeysWithValues: all.compactMap { d in d.code.map { ($0, d) } })

    /// The policy's definition for a task, if it has one.
    public static func definition(for task: TrackableTask) -> TaskDefinition? {
        definition(projectName: task.project.name, projectCode: task.projectCode, taskName: task.task.name)
    }

    public static func definition(projectName: String, projectCode: String?, taskName: String) -> TaskDefinition? {
        // A code anywhere it's written wins: "[TB-DP-12] Billing", or a
        // project code of "TB-DP-12".
        let codes = [projectCode, projectName, taskName].compactMap { $0 }.compactMap(code(in:))
        if let found = codes.lazy.compactMap({ byCode[$0] }).first { return found }

        let project = normalized(stripCode(projectName))
        let task = normalized(taskName)
        let names = [project, task]
        if names.contains(where: { words($0).contains("pto") || $0.contains("paid time off") }) { return pto }
        if names.contains(where: { $0.contains("cross-divisional") || $0.contains("cross divisional") }) { return crossDivisional }

        // Retired buckets: the plain names, with no current code. A bare
        // "TB-DP" code (no number) is the generic bucket too.
        let bareDP = [projectCode, projectName].compactMap { $0 }.contains { normalized($0).contains("tb-dp") }
        if project == "digital products" || task == "digital products" || (bareDP && codes.isEmpty) {
            return retiredDigitalProducts
        }
        if ["business dev", "business development"].contains(project) || ["business dev", "business development"].contains(task) {
            return retiredBusinessDev
        }
        return nil
    }

    /// "TB-DP-07" from "[TB-DP-07] …", "TB-DP-7" or "tb-dp-07", padded to two digits.
    static func code(in text: String) -> String? {
        guard let match = text.uppercased().firstMatch(of: /TB-DP-(\d{1,2})(?!\d)/) else { return nil }
        guard let number = Int(match.1) else { return nil }
        return String(format: "TB-DP-%02d", number)
    }

    private static func stripCode(_ name: String) -> String {
        guard name.hasPrefix("["), let close = name.firstIndex(of: "]") else { return name }
        return String(name[name.index(after: close)...])
    }

    private static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ s: String) -> [Substring] {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
