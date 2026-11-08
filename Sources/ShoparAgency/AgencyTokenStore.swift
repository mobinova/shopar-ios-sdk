import Foundation
import Security

struct AgencyStoredTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresAt: Int64
    let refreshTokenExpiresAt: Int64
}

enum AgencyKeychainError: Error {
    case invalidData
    case keychain(OSStatus)
}

/// Uses the host application's standard Keychain boundary; this SDK does not add token encryption.
final class AgencyTokenStore: @unchecked Sendable {
    private let service: String
    private let account = "agency-session"
    private let lock = NSLock()

    init(configuration: AgencyConfiguration) {
        service = "com.mobinova.shopar.agency.\(configuration.grpcHost).\(configuration.grpcPort).\(configuration.appID)"
    }

    func read() throws -> AgencyStoredTokens? {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AgencyKeychainError.keychain(status) }
        guard let data = result as? Data else { throw AgencyKeychainError.invalidData }
        return try JSONDecoder().decode(AgencyStoredTokens.self, from: data)
    }

    func write(_ tokens: AgencyStoredTokens) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(tokens)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AgencyKeychainError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw AgencyKeychainError.keychain(status)
        }
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AgencyKeychainError.keychain(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}
