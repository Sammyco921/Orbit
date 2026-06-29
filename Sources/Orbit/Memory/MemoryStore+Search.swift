import Foundation
import GRDB

// MARK: - FTS5 Sanitization

private func sanitizeFTSQuery(_ query: String) -> String {
    let stripped = query.unicodeScalars.filter { c in
        let isAlphanumeric = CharacterSet.alphanumerics.contains(c)
        let isAllowedPunct = c == " " || c == "'" || c == "-" || c == "_"
        return isAlphanumeric || isAllowedPunct
    }
    let result = String(String.UnicodeScalarView(stripped))
    return result.replacingOccurrences(of: "'", with: "''")
}

// MARK: - Search & Read

extension MemoryStore {
    func buildVectorIndex() throws {
        if try vectorIndex.needsRebuild() {
            try vectorIndex.build()
        }
    }

    func getAllItems() throws -> [MemoryItem] {
        try db.read { db in
            try MemoryItem.fetchAll(db, sql: """
                SELECT id, conversationId, messageId, type, role, content, createdAt
                FROM memory_items
                ORDER BY createdAt DESC
            """)
        }
    }

    func deleteItems(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        try db.write { db in
            try db.execute(sql: "DELETE FROM memory_items WHERE id IN (\(placeholders))", arguments: StatementArguments(ids))
        }
    }

    func getSummary(conversationId: String) throws -> String? {
        try db.read { db in
            try String.fetchOne(db, sql: """
                SELECT summary FROM conversation_summaries WHERE conversationId = ?
            """, arguments: [conversationId])
        }
    }

    func semanticSearch(embedding: [Float], limit: Int, conversationId: String?, workspaceId: String? = nil) throws -> [MemoryItem] {
        let items = try fetchItems(conversationId: conversationId, workspaceId: workspaceId)
        guard !items.isEmpty else { return [] }

        let itemSet = try prefilterWithIndex(embedding: embedding, itemIds: Set(items.map { $0.id }))
        let filtered = itemSet.isEmpty ? items : items.filter { itemSet.contains($0.id) }
        guard !filtered.isEmpty else { return [] }

        let ids = filtered.map { $0.id }
        let embeddings = try loadEmbeddings(ids: ids)
        let scored = filtered.compactMap { item -> (MemoryItem, Float)? in
            guard let stored = embeddings[item.id] else { return nil }
            return (item, cosineSimilarity(embedding, stored))
        }
        var results = scored.sorted { $0.1 > $1.1 }
        results = rerank(results, query: nil)
        return results.prefix(limit).map { $0.0 }
    }

    func textSearch(query: String, limit: Int) throws -> [MemoryItem] {
        let sanitized = sanitizeFTSQuery(query)
        return try db.read { db in
            try MemoryItem.fetchAll(db, sql: """
                SELECT m.id, m.conversationId, m.messageId, m.type, m.role, m.content, m.createdAt
                FROM memory_items m
                INNER JOIN memory_fts fts ON fts.rowid = m.rowid
                WHERE memory_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """, arguments: [sanitized, limit])
        }
    }

    func hybridSearch(embedding: [Float], query: String?, limit: Int, conversationId: String?, workspaceId: String? = nil, semanticWeight: Float = 0.5) throws -> [MemoryItem] {
        var textMatchIds: Set<String> = []
        if let query, !query.isEmpty {
            let sanitized = sanitizeFTSQuery(query)
            textMatchIds = try db.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT m.id FROM memory_items m
                    INNER JOIN memory_fts fts ON fts.rowid = m.rowid
                    WHERE memory_fts MATCH ?
                    ORDER BY rank
                    LIMIT ?
                """, arguments: [sanitized, limit * 4])
                return Set(rows.compactMap { $0["id"] as? String })
            }
        }

        let items = try fetchItems(conversationId: conversationId, workspaceId: workspaceId)
        guard !items.isEmpty else { return [] }

        let itemSet = try prefilterWithIndex(embedding: embedding, itemIds: Set(items.map { $0.id }))
        let textOnlyIds = textMatchIds.subtracting(itemSet)
        let combined = itemSet.union(textOnlyIds)
        let filtered = combined.isEmpty ? items : items.filter { combined.contains($0.id) }
        guard !filtered.isEmpty else { return [] }

        let ids = filtered.map { $0.id }
        let embeddings = try loadEmbeddings(ids: ids)
        let scored = filtered.compactMap { item -> (MemoryItem, Float)? in
            guard let stored = embeddings[item.id] else { return nil }
            let semantic = cosineSimilarity(embedding, stored)
            let textScore: Float = textMatchIds.contains(item.id) ? 1.0 : 0.0
            return (item, semantic * semanticWeight + textScore * (1 - semanticWeight))
        }
        var results = scored.sorted { $0.1 > $1.1 }
        results = rerank(results, query: query)
        return results.prefix(limit).map { $0.0 }
    }

    func chunkContent(_ content: String, chunkSize: Int = 512, overlap: Int = 64) -> [String] {
        guard content.count > chunkSize else { return [content] }
        let words = content.split(separator: " ").map(String.init)
        guard words.count > 1 else { return [content] }

        let targetWords = max(1, chunkSize / 5)
        let overlapWords = max(1, overlap / 5)
        var chunks: [String] = []
        var start = 0
        while start < words.count {
            let end = min(start + targetWords, words.count)
            chunks.append(words[start..<end].joined(separator: " "))
            if end >= words.count { break }
            start = end - overlapWords
        }
        return chunks
    }

    private func fetchItems(conversationId: String?, workspaceId: String?) throws -> [MemoryItem] {
        try db.read { db in
            if let conversationId {
                return try MemoryItem.fetchAll(db, sql: """
                    SELECT id, conversationId, messageId, type, role, content, createdAt
                    FROM memory_items
                    WHERE conversationId = ? AND embedding IS NOT NULL
                    ORDER BY createdAt DESC
                """, arguments: [conversationId])
            } else if let workspaceId {
                return try MemoryItem.fetchAll(db, sql: """
                    SELECT m.id, m.conversationId, m.messageId, m.type, m.role, m.content, m.createdAt
                    FROM memory_items m
                    INNER JOIN conversations c ON c.id = m.conversationId
                    WHERE c.workspaceId = ? AND m.embedding IS NOT NULL
                    ORDER BY m.createdAt DESC
                """, arguments: [workspaceId])
            } else {
                return try MemoryItem.fetchAll(db, sql: """
                    SELECT id, conversationId, messageId, type, role, content, createdAt
                    FROM memory_items
                    WHERE embedding IS NOT NULL
                    ORDER BY createdAt DESC
                    LIMIT 1000
                """)
            }
        }
    }

    private func loadEmbeddings(ids: [String]) throws -> [String: [Float]] {
        guard !ids.isEmpty else { return [:] }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, embedding FROM memory_items WHERE id IN (\(placeholders))", arguments: StatementArguments(ids))
            var result: [String: [Float]] = [:]
            for row in rows {
                guard let id: String = row["id"] else { continue }
                guard let blob: Data = row["embedding"], !blob.isEmpty else { continue }
                result[id] = blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            }
            return result
        }
    }

    private func prefilterWithIndex(embedding: [Float], itemIds: Set<String>) throws -> Set<String> {
        if try vectorIndex.needsRebuild() {
            try vectorIndex.build()
        }
        let indexed = try vectorIndex.search(query: embedding)
        guard !indexed.isEmpty else { return itemIds }
        return itemIds.intersection(indexed)
    }

    private func rerank(_ scored: [(MemoryItem, Float)], query: String?) -> [(MemoryItem, Float)] {
        let now = Date().timeIntervalSince1970
        let day: TimeInterval = 86400
        return scored.map { item, score in
            var boost: Float = 0
            let age = now - item.createdAt
            if age < day { boost += 0.2 } else if age < 7 * day { boost += 0.1 }
            if let query, !query.isEmpty {
                let content = item.content.lowercased()
                for token in query.lowercased().split(separator: " ") where content.contains(token) {
                    boost += 0.05
                }
            }
            return (item, score + boost)
        }
    }

    func embeddingData(_ embedding: [Float]?) -> Data? {
        guard let embedding else { return nil }
        return embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }
}
