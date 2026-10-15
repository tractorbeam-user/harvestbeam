import Foundation

/// The slice of the Harvest API the app uses. `HarvestClient` talks to the real
/// API; `DemoHarvestService` fakes it with sample data.
public protocol HarvestService: Sendable {
    func currentUser() async throws -> HarvestUser
    func company() async throws -> Company
    func projectAssignments() async throws -> [ProjectAssignment]
    func timeEntries(userID: Int, from: LocalDate, to: LocalDate) async throws -> [TimeEntry]
    func startTimer(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?) async throws -> TimeEntry
    /// Creates a stopped entry with hours already logged.
    func createEntry(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?, hours: Double) async throws -> TimeEntry
    func restartTimer(id: Int) async throws -> TimeEntry
    func stopTimer(id: Int) async throws -> TimeEntry
    func updateNotes(id: Int, notes: String) async throws -> TimeEntry
    /// Changes an entry's task, notes and (for stopped entries) hours.
    func updateEntry(id: Int, projectID: Int, taskID: Int, notes: String, hours: Double?) async throws -> TimeEntry
    func deleteEntry(id: Int) async throws
}

public enum HarvestError: LocalizedError, Equatable {
    case unauthorized
    case forbidden(String?)
    case rateLimited
    case server(status: Int, message: String?)
    case network(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Harvest didn't accept that token. Check it hasn't been revoked."
        case .forbidden(let message):
            return message ?? "Your Harvest account doesn't allow that."
        case .rateLimited:
            return "Harvest is rate limiting requests. Try again in a few seconds."
        case .server(let status, let message):
            return message ?? "Harvest returned an error (\(status))."
        case .network(let message):
            return message
        case .decoding(let message):
            return "Unexpected response from Harvest. \(message)"
        }
    }
}

/// Harvest API v2 over a personal access token.
/// Docs: https://help.getharvest.com/api-v2/
public struct HarvestClient: HarvestService {
    public let token: String
    public let accountID: Int

    static let apiBase = URL(string: "https://api.harvestapp.com/v2/")!
    static let idBase = URL(string: "https://id.getharvest.com/api/v2/")!
    static let userAgent = "Harvestbeam (macOS and iOS time tracker)"

    public init(token: String, accountID: Int) {
        self.token = token
        self.accountID = accountID
    }

    // MARK: Accounts (Harvest ID)

    /// Lists the Harvest accounts a token can reach, so the user only has to paste a token.
    public static func accounts(token: String) async throws -> [HarvestAccount] {
        struct Response: Decodable { let accounts: [HarvestAccount] }
        var request = URLRequest(url: idBase.appendingPathComponent("accounts"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let response: Response = try await perform(request)
        return response.accounts.filter { $0.product == "harvest" }
    }

    // MARK: HarvestService

    public func currentUser() async throws -> HarvestUser {
        try await send("GET", "users/me")
    }

    public func company() async throws -> Company {
        try await send("GET", "company")
    }

    public func projectAssignments() async throws -> [ProjectAssignment] {
        struct Page: Decodable { let projectAssignments: [ProjectAssignment]; let nextPage: Int? }
        var all: [ProjectAssignment] = []
        var page: Int? = 1
        while let current = page {
            let response: Page = try await send("GET", "users/me/project_assignments", query: [
                URLQueryItem(name: "page", value: String(current)),
                URLQueryItem(name: "per_page", value: "2000"),
            ])
            all += response.projectAssignments
            page = response.nextPage
        }
        return all
    }

    public func timeEntries(userID: Int, from: LocalDate, to: LocalDate) async throws -> [TimeEntry] {
        struct Page: Decodable { let timeEntries: [TimeEntry]; let nextPage: Int? }
        var all: [TimeEntry] = []
        var page: Int? = 1
        while let current = page {
            let response: Page = try await send("GET", "time_entries", query: [
                URLQueryItem(name: "user_id", value: String(userID)),
                URLQueryItem(name: "from", value: from.description),
                URLQueryItem(name: "to", value: to.description),
                URLQueryItem(name: "page", value: String(current)),
                URLQueryItem(name: "per_page", value: "2000"),
            ])
            all += response.timeEntries
            page = response.nextPage
        }
        return all
    }

    /// Creates an entry without hours, which Harvest starts as a running timer.
    public func startTimer(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?) async throws -> TimeEntry {
        struct Body: Encodable { let projectId: Int; let taskId: Int; let spentDate: LocalDate; let notes: String? }
        return try await send("POST", "time_entries", body: Body(projectId: projectID, taskId: taskID, spentDate: spentDate, notes: notes))
    }

    public func createEntry(projectID: Int, taskID: Int, spentDate: LocalDate, notes: String?, hours: Double) async throws -> TimeEntry {
        struct Body: Encodable { let projectId: Int; let taskId: Int; let spentDate: LocalDate; let notes: String?; let hours: Double }
        return try await send("POST", "time_entries", body: Body(projectId: projectID, taskId: taskID, spentDate: spentDate, notes: notes, hours: hours))
    }

    public func restartTimer(id: Int) async throws -> TimeEntry {
        try await send("PATCH", "time_entries/\(id)/restart")
    }

    public func stopTimer(id: Int) async throws -> TimeEntry {
        try await send("PATCH", "time_entries/\(id)/stop")
    }

    public func updateNotes(id: Int, notes: String) async throws -> TimeEntry {
        struct Body: Encodable { let notes: String }
        return try await send("PATCH", "time_entries/\(id)", body: Body(notes: notes))
    }

    public func updateEntry(id: Int, projectID: Int, taskID: Int, notes: String, hours: Double?) async throws -> TimeEntry {
        struct Body: Encodable { let projectId: Int; let taskId: Int; let notes: String; let hours: Double? }
        return try await send("PATCH", "time_entries/\(id)", body: Body(projectId: projectID, taskId: taskID, notes: notes, hours: hours))
    }

    public func deleteEntry(id: Int) async throws {
        struct Ignored: Decodable {}
        var request = URLRequest(url: Self.apiBase.appendingPathComponent("time_entries/\(id)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(String(accountID), forHTTPHeaderField: "Harvest-Account-Id")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        // Harvest answers 200 with an empty body, so don't decode it.
        let _: Ignored? = try await Self.perform(request, allowEmpty: true)
    }

    // MARK: Transport

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method, path, query: query, body: Optional<String>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, query: [URLQueryItem] = [], body: B?) async throws -> T {
        var components = URLComponents(url: Self.apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(String(accountID), forHTTPHeaderField: "Harvest-Account-Id")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await Self.perform(request)
    }

    private static func perform<T: Decodable>(_ request: URLRequest, allowEmpty: Bool) async throws -> T? {
        do {
            let value: T = try await perform(request)
            return value
        } catch HarvestError.decoding where allowEmpty {
            return nil
        }
    }

    private static func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw HarvestError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = errorMessage(from: data)
            switch status {
            case 401: throw HarvestError.unauthorized
            case 403: throw HarvestError.forbidden(message)
            case 429: throw HarvestError.rateLimited
            default: throw HarvestError.server(status: status, message: message)
            }
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw HarvestError.decoding(String(describing: error))
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (object["message"] ?? object["error_description"] ?? object["error"]) as? String
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}
