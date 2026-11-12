import Foundation
import Security

public struct Credentials: Codable, Sendable, Equatable {
    public let token: String
    public let accountID: Int
    public let accountName: String

    public init(token: String, accountID: Int, accountName: String) {
        self.token = token
        self.accountID = accountID
        self.accountName = accountName
    }
}

/// Keeps the Harvest token in the Keychain, never in UserDefaults.
public enum CredentialStore {
    /// Where Harvestbeam keeps it, and where every build kept it before the
    /// beta got its own.
    static let sharedService = "com.tractorbeam.harvestbar"
    /// Each app its own sign-in, like its own settings: signing out of the
    /// beta leaves Harvestbeam signed in.
    static let service = Bundle.main.bundleIdentifier ?? sharedService
    static let account = "harvest-credentials"

    private static func query(_ service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static var baseQuery: [String: Any] { query(service) }

    public static func load() -> Credentials? {
        if let own = load(from: service) { return own }
        // The beta, the first time: start signed in as Harvestbeam was, then
        // keep its own copy.
        // Only once: after signing out of the beta it stays signed out.
        let copiedKey = "credentials.copiedFromShared"
        guard service != sharedService, !UserDefaults.standard.bool(forKey: copiedKey),
              let shared = load(from: sharedService) else { return nil }
        UserDefaults.standard.set(true, forKey: copiedKey)
        try? save(shared)
        return shared
    }

    private static func load(from service: String) -> Credentials? {
        var query = query(service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    public static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Couldn't save the token to the Keychain (\(status)).",
            ])
        }
    }

    public static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
