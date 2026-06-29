import Foundation
import GRDB

// MARK: - Global Memory, Preferences, Facts, Tool Usage

extension MemoryStore {
    func storeGlobalItem(content: String, type: String = "fact", role: String? = nil, embedding: [Float]? = nil, source: String? = nil, workspaceId: String? = nil) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO global_memory_items (id, type, role, content, embedding, source, workspaceId, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                UUID().uuidString, type, role, content, embeddingData(embedding), source, workspaceId, Date().timeIntervalSince1970
            ])
        }
    }

    func searchGlobalItems(limit: Int = 10, workspaceId: String? = nil) throws -> [MemoryItem] {
        try db.read { db in
            let sql: String
            let args: StatementArguments
            if let wsId = workspaceId {
                sql = """
                    SELECT id, '' AS conversationId, NULL AS messageId, type, role, content, createdAt
                    FROM global_memory_items
                    WHERE workspaceId IS NULL OR workspaceId = ?
                    ORDER BY createdAt DESC
                    LIMIT ?
                """
                args = [wsId, limit]
            } else {
                sql = """
                    SELECT id, '' AS conversationId, NULL AS messageId, type, role, content, createdAt
                    FROM global_memory_items
                    ORDER BY createdAt DESC
                    LIMIT ?
                """
                args = [limit]
            }
            let rows = try Row.fetchAll(db, sql: sql, arguments: args)
            return rows.map { row in
                let id: String = row["id"]
                let type: String = row["type"]
                let role: String? = row["role"]
                let content: String = row["content"]
                let createdAt: TimeInterval = row["createdAt"]
                return MemoryItem(
                    id: id, conversationId: "", messageId: nil,
                    type: type, role: role, content: content, createdAt: createdAt
                )
            }
        }
    }

    func deleteGlobalItems(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try db.write { db in
            try db.execute(sql: "DELETE FROM global_memory_items WHERE id IN (\(placeholders))", arguments: StatementArguments(ids))
        }
    }

    func setPreference(key: String, value: String) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO user_preferences (key, value, updatedAt)
                VALUES (?, ?, ?)
            """, arguments: [key, value, Date().timeIntervalSince1970])
        }
    }

    func getPreference(key: String) throws -> String? {
        try db.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM user_preferences WHERE key = ?", arguments: [key])
        }
    }

    func getAllPreferences() throws -> [(String, String)] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT key, value FROM user_preferences ORDER BY key")
            return rows.map { row in
                let key: String = row["key"]
                let value: String = row["value"]
                return (key, value)
            }
        }
    }

    func storeUserFact(fact: String, category: String = "preference", confidence: Float = 0.5, source: String? = nil) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO user_facts (fact, category, confidence, source, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [fact, category, confidence, source, Date().timeIntervalSince1970, Date().timeIntervalSince1970])
        }
    }

    func getUserFacts(category: String? = nil) throws -> [(id: Int64, fact: String, category: String, confidence: Float)] {
        try db.read { db in
            let rows: [Row]
            if let cat = category {
                rows = try Row.fetchAll(db, sql: "SELECT id, fact, category, confidence FROM user_facts WHERE category = ? ORDER BY confidence DESC LIMIT 50", arguments: [cat])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT id, fact, category, confidence FROM user_facts ORDER BY confidence DESC LIMIT 50")
            }
            return rows.map { row in
                let id: Int64 = row["id"]
                let fact: String = row["fact"]
                let cat: String = row["category"]
                let conf: Double = row["confidence"]
                return (id, fact, cat, Float(conf))
            }
        }
    }

    func deleteUserFact(id: Int64) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM user_facts WHERE id = ?", arguments: [id])
        }
    }
}
