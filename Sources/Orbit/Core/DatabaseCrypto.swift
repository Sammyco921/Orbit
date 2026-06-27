import Foundation
import CryptoKit
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "db-crypto")

final class DatabaseCrypto {
    private static let keychainAccount = "database_encryption_key"
    private let keychain = KeychainManager()
    private let key: SymmetricKey

    init(customKey: String? = nil) {
        if let custom = customKey, let data = Data(base64Encoded: custom) {
            key = SymmetricKey(data: data)
            log.notice("DatabaseCrypto initialized with provided key")
        } else if let stored = try? keychain.read(account: Self.keychainAccount),
                  let data = Data(base64Encoded: stored) {
            key = SymmetricKey(data: data)
            log.notice("DatabaseCrypto initialized from Keychain")
        } else {
            let newKey = SymmetricKey(size: .bits256)
            key = newKey
            let data = newKey.withUnsafeBytes { Data($0) }
            try? keychain.store(key: data.base64EncodedString(), for: Self.keychainAccount)
            log.notice("Generated new database encryption key")
        }
    }

    func encrypt(_ plaintext: String) throws -> Data {
        let data = Data(plaintext.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined ?? Data()
    }

    func decrypt(_ data: Data) throws -> String {
        let sealed = try AES.GCM.SealedBox(combined: data)
        let plain = try AES.GCM.open(sealed, using: key)
        return String(data: plain, encoding: .utf8) ?? ""
    }
}
