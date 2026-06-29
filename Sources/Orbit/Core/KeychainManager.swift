import Foundation
import Security
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "keychain")

final class KeychainManager {
    private let service = "com.orbit.api-keys"

    enum KeychainError: Error {
        case notFound
        case unhandledError(OSStatus)
    }

    func store(key: String, for account: String) throws {
        // Delete existing before adding
        try? delete(account: account)

        guard let data = key.data(using: .utf8) else {
            throw KeychainError.unhandledError(errSecInvalidData)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            log.error("Failed to store key for \(account): \(status)")
            throw KeychainError.unhandledError(status)
        }
    }

    func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unhandledError(status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            throw KeychainError.unhandledError(errSecDecode)
        }

        return key
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status)
        }
    }
}
