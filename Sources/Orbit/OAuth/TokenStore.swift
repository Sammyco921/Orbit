import Foundation
import GRDB
import OSLog
import Security

private let log = Logger(subsystem: "com.orbit", category: "token-store")

final class TokenStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) { self.db = db }

    func saveToken(_ credential: OAuthCredential) throws {
        let encoder = JSONEncoder()
        let tokenData = try encoder.encode(credential.token)
        let tokenJSON = String(data: tokenData, encoding: .utf8) ?? "{}"

        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO oauth_credentials (id, providerId, accountName, workspaceId, tokenJSON, scopesJSON, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                credential.id, credential.providerId, credential.accountName,
                credential.workspaceId, tokenJSON,
                try encoder.encode(credential.scopes).base64EncodedString(),
                credential.createdAt.timeIntervalSince1970,
                credential.updatedAt.timeIntervalSince1970
            ])
        }

        try storeInKeychain(credential)
    }

    func credential(providerId: String, workspaceId: String?) -> OAuthCredential? {
        try? db.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM oauth_credentials
                WHERE providerId = ? AND workspaceId IS ? ORDER BY updatedAt DESC LIMIT 1
            """, arguments: [providerId, workspaceId])
            guard let row else { return nil }
            return decodeCredential(from: row)
        }
    }

    func credential(id: String) -> OAuthCredential? {
        try? db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM oauth_credentials WHERE id = ?", arguments: [id])
            guard let row else { return nil }
            return decodeCredential(from: row)
        }
    }

    func allCredentials(workspaceId: String?) -> [OAuthCredential] {
        (try? db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM oauth_credentials WHERE workspaceId IS ? ORDER BY updatedAt DESC
            """, arguments: [workspaceId])
            return rows.compactMap(decodeCredential(from:))
        }) ?? []
    }

    func deleteCredential(id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(query as CFDictionary)

        try db.write { db in
            try db.execute(sql: "DELETE FROM oauth_credentials WHERE id = ?", arguments: [id])
        }
    }

    func deleteCredentials(providerId: String, workspaceId: String?) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM oauth_credentials WHERE providerId = ? AND workspaceId IS ?", arguments: [providerId, workspaceId])
        }
    }

    // MARK: - Keychain

    private let keychainService = "com.orbit.oauth"

    private func storeInKeychain(_ credential: OAuthCredential) throws {
        guard let data = try? JSONEncoder().encode(credential) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: credential.id,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            log.warning("Keychain store failed with status \(status)")
        }
    }

    func retrieveFromKeychain(id: String) -> OAuthCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    private func decodeCredential(from row: Row) -> OAuthCredential? {
        guard let id: String = row["id"],
              let providerId: String = row["providerId"],
              let tokenJSON: String = row["tokenJSON"],
              let tokenData = tokenJSON.data(using: .utf8),
              let token = try? JSONDecoder().decode(OAuthToken.self, from: tokenData),
              let scopesB64: String = row["scopesJSON"],
              let scopesData = Data(base64Encoded: scopesB64),
              let scopes = try? JSONDecoder().decode([String].self, from: scopesData)
        else { return nil }

        return OAuthCredential(
            id: id,
            providerId: providerId,
            accountName: row["accountName"],
            workspaceId: row["workspaceId"],
            token: token,
            scopes: scopes,
            createdAt: Date(timeIntervalSince1970: row["createdAt"]),
            updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
        )
    }
}
