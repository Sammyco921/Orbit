import Testing
import Foundation
import GRDB
@testable import Orbit

struct MemoryPerformanceTests {

    @Test func semanticSearchPerformance() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let convId = UUID().uuidString
        try createConversation(db: db, id: convId)

        for i in 0..<100 {
            try store.storeMessage(
                conversationId: convId,
                messageId: UUID().uuidString,
                role: i.isMultiple(of: 2) ? "user" : "assistant",
                content: "Memory item number \(i) discussing topic \(i % 10).",
                embedding: randomEmbedding()
            )
        }

        let queryEmbedding = randomEmbedding()
        try store.buildVectorIndex()
        let start = CFAbsoluteTimeGetCurrent()
        let results = try store.semanticSearch(embedding: queryEmbedding, limit: 5, conversationId: convId)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(results.count <= 5)
        #expect(elapsed < 200, "Semantic search over 100 items took \(elapsed)ms — expected < 200ms")
    }

    @Test func textSearchPerformance() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let convId = UUID().uuidString
        try createConversation(db: db, id: convId)

        for i in 0..<50 {
            try store.storeMessage(
                conversationId: convId,
                messageId: UUID().uuidString,
                role: "user",
                content: "Discussion about topic \(i). Some interesting points were raised about technology and science.",
                embedding: nil
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let results = try store.textSearch(query: "technology", limit: 5)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(!results.isEmpty, "Expected some results matching 'technology'")
        #expect(elapsed < 200, "Text search took \(elapsed)ms — expected < 200ms for 50 items")
    }

    @Test func chunkingSplitsLongContent() {
        let db = try! OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let content = Array(repeating: "word", count: 500).joined(separator: " ")
        let chunks = store.chunkContent(content, chunkSize: 100, overlap: 20)
        #expect(chunks.count > 1, "Content of 500 chars should be split into multiple chunks")
    }

    @Test func chunkingPreservesShortContent() {
        let db = try! OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let chunks = store.chunkContent("short content")
        #expect(chunks.count == 1)
        #expect(chunks[0] == "short content")
    }

    @Test func hybridSearchCombinesTextAndSemantic() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let convId = UUID().uuidString
        try createConversation(db: db, id: convId)

        let emb1 = randomEmbedding()
        let emb2 = randomEmbedding()
        let emb3 = randomEmbedding()

        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "user", content: "The weather today is sunny and warm", embedding: emb1)
        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "user", content: "I love programming in Swift", embedding: emb2)
        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "user", content: "Weather forecast for the weekend", embedding: emb3)

        // Verify using direct DB query
        let itemCount = try await db.db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM memory_items WHERE conversationId = ?", arguments: [convId])
        }
        #expect(itemCount == 3)

        let embedCount = try await db.db.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM memory_items WHERE conversationId = ? AND embedding IS NOT NULL", arguments: [convId])
        }
        #expect(embedCount == 3, "Embedding IS NOT NULL should return 3")

        let blobCount = try await db.db.read {
            let rows = try Row.fetchAll($0, sql: "SELECT id, length(embedding) AS len FROM memory_items WHERE conversationId = ?", arguments: [convId])
            return rows.filter { ($0["len"] as? Int64 ?? 0) > 0 }.count
        }
        #expect(blobCount == 3, "Embedding BLOB length > 0 should be 3")

        // Direct check: load embedding from first stored item
        let firstId = try await db.db.read { db in
            try String.fetchOne(db, sql: "SELECT id FROM memory_items WHERE conversationId = ? LIMIT 1", arguments: [convId])
        }
        if let firstId {
            let blob = try await db.db.read { db in
                try Data.fetchOne(db, sql: "SELECT embedding FROM memory_items WHERE id = ?", arguments: [firstId])
            }
            #expect(blob != nil, "Embedding BLOB should be non-nil")
            #expect(blob?.isEmpty == false, "Embedding BLOB should not be empty")
            if let blob, !blob.isEmpty {
                let floats = blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                #expect(floats.count == 128, "Should have 128 floats, got \(floats.count)")
            }
        }

        // Test fetchItems directly
        let q = "SELECT COUNT(*) FROM memory_items WHERE conversationId = ? AND encoding IS NOT NULL"
        let embedCount2 = try await db.db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_items WHERE conversationId = ? AND embedding IS NOT NULL", arguments: [convId])
        }
        #expect(embedCount2 == 3, "embedding IS NOT NULL should work in raw SQL")

        let ids = try await db.db.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM memory_items WHERE conversationId = ?", arguments: [convId])
        }
        #expect(ids.count == 3, "Should have 3 IDs")

        for id in ids {
            let blob = try await db.db.read { db in
                try? Data.fetchOne(db, sql: "SELECT embedding FROM memory_items WHERE id = ?", arguments: [id])
            }
            #expect(blob != nil, "Embedding for \(id) should be non-nil")
        }

        let queryEmbedding = emb1
        let allItems = try store.semanticSearch(embedding: queryEmbedding, limit: 5, conversationId: convId)
        #expect(!allItems.isEmpty, "Should find at least 1 item with matching embedding")

        let results = try store.hybridSearch(embedding: queryEmbedding, query: "weather", limit: 5, conversationId: convId, semanticWeight: 0.3)
        #expect(!results.isEmpty, "Hybrid search should return results")
    }

    @Test func memoryTypesStoredCorrectly() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())
        let store = MemoryStore(db: db.db)
        let convId = UUID().uuidString
        try createConversation(db: db, id: convId)

        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "user", content: "episodic memory", embedding: nil, type: .episodic)
        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "assistant", content: "semantic memory", embedding: nil, type: .semantic)
        try store.storeMessage(conversationId: convId, messageId: UUID().uuidString, role: "system", content: "procedural memory", embedding: nil, type: .procedural)

        let all = try await db.db.read { db in
            try Row.fetchAll(db, sql: "SELECT type FROM memory_items WHERE conversationId = ? ORDER BY createdAt", arguments: [convId])
        }
        #expect(all.count == 3)
        #expect(all[0]["type"] as! String == "episodic")
        #expect(all[1]["type"] as! String == "semantic")
        #expect(all[2]["type"] as! String == "procedural")
    }

    private func createConversation(db: OrbitDatabase, id: String) throws {
        try db.db.write { db in
            try db.execute(sql: "INSERT INTO conversations (id, title, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                          arguments: [id, "test", Date().timeIntervalSince1970, Date().timeIntervalSince1970])
        }
    }

    private func randomEmbedding() -> [Float] {
        (0..<128).map { _ in Float.random(in: -1...1) }
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit_test_mem_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("sqlite")
    }
}
