import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "memory")

enum MemoryType: String, Codable, CaseIterable {
    case episodic
    case semantic
    case procedural
    case summary
}

struct MemoryItem: Identifiable, Codable, FetchableRecord {
    let id: String
    let conversationId: String
    let messageId: String?
    let type: String
    let role: String?
    let content: String
    let createdAt: TimeInterval
}

final class MemoryStore {
    let db: DatabaseQueue
    let vectorIndex: VectorIndex

    init(db: DatabaseQueue) {
        self.db = db
        self.vectorIndex = VectorIndex(db: db)
    }

    // MARK: - Store

    func storeMessage(conversationId: String, messageId: String, role: String, content: String, embedding: [Float]?, type: MemoryType = .episodic) throws {
        let memoryType = type.rawValue
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO memory_items (id, conversationId, messageId, type, role, content, embedding, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                UUID().uuidString,
                conversationId,
                messageId,
                memoryType,
                role,
                content,
                embeddingData(embedding),
                Date().timeIntervalSince1970
            ])
        }
    }

    func storeSummary(conversationId: String, summary: String, messageCount: Int) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO conversation_summaries (conversationId, summary, messageCount, updatedAt)
                VALUES (?, ?, ?, ?)
            """, arguments: [
                conversationId,
                summary,
                messageCount,
                Date().timeIntervalSince1970
            ])
        }
    }
}
