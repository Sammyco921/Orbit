import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "database")

/// Errors originating from database backup, integrity, or recovery operations.
enum DatabaseError: Error, LocalizedError {
    case integrityCheckFailed(String)
    case backupFailed(String)
    case recoveryFailed(String)

    var errorDescription: String? {
        switch self {
        case .integrityCheckFailed(let detail): return "Database integrity check failed: \(detail)"
        case .backupFailed(let detail): return "Database backup failed: \(detail)"
        case .recoveryFailed(let detail): return "Database recovery failed: \(detail)"
        }
    }
}

/// Primary persistence layer — SQLite via GRDB with encryption, integrity checks, and backup recovery.
final class OrbitDatabase {
    let db: DatabaseQueue
    private(set) var isDegraded = false
    let storageURL: URL
    let crypto: DatabaseCrypto?

    init(storageURL: URL? = nil, encryptionKey: String? = nil) throws {
        let url = storageURL ?? Self.storageURL
        self.storageURL = url
        if let key = encryptionKey, !key.isEmpty {
            crypto = DatabaseCrypto(customKey: key)
        } else {
            crypto = nil
        }
        let parentDir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode=WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint=1000")
        }
        db = try DatabaseQueue(path: url.path, configuration: config)
        try runIntegrityCheck()
        if storageURL == nil {
            Self.backupIfExists(url: url)
        }
        try runMigrations()
        if storageURL == nil {
            try migrateFromJSON()
        }
    }

    // MARK: - Health

    private func runIntegrityCheck() throws {
        do {
            let result: String = try db.read { db in
                try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "unknown"
            }
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != "ok" {
                isDegraded = true
                log.error("Database integrity check failed: \(trimmed)")
            } else {
                log.notice("Database integrity check passed")
            }
        } catch {
            isDegraded = true
            log.error("Could not run integrity check: \(error.localizedDescription)")
        }
    }

    private static func backupIfExists(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let backupURL = Self.backupURL
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
            log.notice("Backed up database to \(backupURL.path)")
        } catch {
            log.warning("Could not create database backup: \(error.localizedDescription)")
        }
    }

    func backup() throws {
        let url = storageURL
        let backupURL = Self.backupURL
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                log.warning("No database file to back up at \(url.path)")
                return
            }
            let parentDir = backupURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
            log.notice("Database backed up to \(backupURL.path)")
        } catch {
            throw DatabaseError.backupFailed(error.localizedDescription)
        }
    }

    func attemptRecovery() -> Bool {
        guard isDegraded else { return true }
        do {
            let backupURL = Self.backupURL
            guard FileManager.default.fileExists(atPath: backupURL.path) else {
                log.error("No backup available for recovery")
                return false
            }
            let url = storageURL
            _ = try? FileManager.default.removeItem(at: url)
            try FileManager.default.copyItem(at: backupURL, to: url)
            log.notice("Recovered database from backup")
            isDegraded = false
            return true
        } catch {
            log.error("Recovery failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - JSON Migration

    private func migrateFromJSON() throws {
        let count = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM conversations") } ?? 0
        guard count == 0 else { return }

        let jsonURL = Self.jsonStorageURL
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return }

        guard let data = try? Data(contentsOf: jsonURL),
              let conversations = try? JSONDecoder().decode([Conversation].self, from: data)
        else {
            log.warning("Found conversations.json but could not decode it — skipping migration")
            return
        }

        try db.write { db in
            for conversation in conversations {
                try insertConversation(conversation, into: db)
            }
        }

        let backupURL = Self.jsonBackupURL
        _ = try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: jsonURL, to: backupURL)
        log.notice("Migrated \(conversations.count) conversations from JSON to SQLite")
    }

    // MARK: - File Paths

    static var storageURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Orbit", isDirectory: true).appendingPathComponent("orbit.sqlite")
    }

    static var backupURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Orbit", isDirectory: true).appendingPathComponent("orbit.sqlite.backup")
    }

    private static var jsonStorageURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Orbit", isDirectory: true).appendingPathComponent("conversations.json")
    }

    private static var jsonBackupURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Orbit", isDirectory: true).appendingPathComponent("conversations.json.migrated")
    }

    // MARK: - JSON Helpers

    func encodeJSON<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func decodeJSON<T: Decodable>(_ string: String?) -> T? {
        guard let string, let data = string.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func intFromRow(_ row: Row, key: String) -> Int {
        if let val = row[key] as? Int { return val }
        if let val = row[key] as? Int64 { return Int(val) }
        return 0
    }
}
