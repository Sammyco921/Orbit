import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "vector")

final class VectorIndex {
    private let db: DatabaseQueue
    private let dims: Int

    private var lastItemCount = 0
    private let minItemsForIndex = 50
    private let maxCentroids = 50

    init(db: DatabaseQueue, dims: Int = 128) {
        self.db = db
        self.dims = dims
    }

    func needsRebuild() throws -> Bool {
        let count = try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM memory_items WHERE embedding IS NOT NULL") ?? 0
        }
        guard count >= minItemsForIndex else { return false }
        guard lastItemCount > 0 else { return true }
        return Float(count) / Float(lastItemCount) > 1.2
    }

    func build() throws {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, embedding FROM memory_items WHERE embedding IS NOT NULL")
        }

        let allIds: [String] = rows.compactMap { $0["id"] as? String }
        var allEmbeddings: [[Float]] = []
        for row in rows {
            guard let blob: Data? = row["embedding"], let blob, !blob.isEmpty else { continue }
            let floats = blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            allEmbeddings.append(floats)
        }

        guard allEmbeddings.count >= minItemsForIndex else { return }
        lastItemCount = allEmbeddings.count

        let k = min(maxCentroids, Int(sqrt(Double(allEmbeddings.count))))
        let (centroids, labels) = kMeans(embeddings: allEmbeddings, k: k)
        guard centroids.count == labels.count / (allEmbeddings.count / max(1, centroids.count)) else { return }

        try db.write { db in
            try db.execute(sql: "DELETE FROM memory_centroids")
            try db.execute(sql: "DELETE FROM memory_clusters")

            for centroid in centroids {
                let data = embeddingData(centroid)
                try db.execute(sql: "INSERT INTO memory_centroids (centroid, num_items) VALUES (?, 0)", arguments: [data])
            }

            var counts = [Int](repeating: 0, count: centroids.count)
            for label in labels { counts[label] += 1 }

            for i in 0..<centroids.count {
                try db.execute(sql: "UPDATE memory_centroids SET num_items = ? WHERE id = ?", arguments: [counts[i], i + 1])
            }

            for (idx, label) in labels.enumerated() {
                try db.execute(sql: "INSERT OR REPLACE INTO memory_clusters (item_id, centroid_id) VALUES (?, ?)", arguments: [allIds[idx], label + 1])
            }
        }

        log.notice("Built vector index with \(k) centroids for \(allEmbeddings.count) items")
    }

    func search(query: [Float], nprobe: Int = 3) throws -> Set<String> {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT id, centroid FROM memory_centroids")
        }
        guard !rows.isEmpty else { return [] }

        var scored: [(Int64, Float)] = []
        for row in rows {
            let id: Int64 = row["id"]
            guard let blob: Data = row["centroid"], !blob.isEmpty else { continue }
            let centroid = blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            scored.append((id, cosineSimilarity(query, centroid)))
        }

        scored.sort { $0.1 > $1.1 }
        let nearest = scored.prefix(nprobe).map { $0.0 }
        guard !nearest.isEmpty else { return [] }

        let placeholders = nearest.map { _ in "?" }.joined(separator: ",")
        let ids = try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT item_id FROM memory_clusters WHERE centroid_id IN (\(placeholders))", arguments: StatementArguments(nearest))
            return rows.compactMap { $0["item_id"] as? String }
        }
        return Set(ids)
    }

    // MARK: - K-Means

    private func kMeans(embeddings: [[Float]], k: Int, maxIterations: Int = 20) -> ([[Float]], [Int]) {
        guard !embeddings.isEmpty, k > 0, k <= embeddings.count else { return ([], []) }

        var centroids = (0..<k).map { _ in normalize(embeddings.randomElement()!) }
        var labels = [Int](repeating: 0, count: embeddings.count)

        for _ in 0..<maxIterations {
            var changed = false
            for i in embeddings.indices {
                var best = 0
                var bestSim: Float = -1
                for j in centroids.indices {
                    let sim = cosineSimilarity(embeddings[i], centroids[j])
                    if sim > bestSim { bestSim = sim; best = j }
                }
                if labels[i] != best { labels[i] = best; changed = true }
            }
            if !changed { break }

            var sums = [[Float]](repeating: [Float](repeating: 0, count: dims), count: k)
            var counts = [Int](repeating: 0, count: k)
            for i in embeddings.indices {
                let label = labels[i]
                for j in 0..<dims { sums[label][j] += embeddings[i][j] }
                counts[label] += 1
            }
            for j in 0..<k where counts[j] > 0 {
                for d in 0..<dims { sums[j][d] /= Float(counts[j]) }
                centroids[j] = normalize(sums[j])
            }
        }

        return (centroids, labels)
    }

    private func normalize(_ v: [Float]) -> [Float] {
        let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return v }
        return v.map { $0 / norm }
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    private func embeddingData(_ embedding: [Float]) -> Data {
        embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
