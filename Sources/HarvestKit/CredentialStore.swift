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
    static let service = "com.tractorbeam.harvestbar"
    static let account = "harvest-credentials"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public static func load() -> Credentials? {
        var query = baseQuery
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
