import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "knowledge")

private let supportedExtensions: Set<String> = ["md", "txt", "swift", "py", "js", "ts", "json", "yaml", "yml", "mdx"]

struct KnowledgeItem: Identifiable {
    let id: String
    let knowledgeBaseId: String
    let filePath: String?
    let chunkIndex: Int
    let content: String
    let createdAt: TimeInterval
}

final class KnowledgeBaseService {
    private let db: DatabaseQueue
    private let embedder: EmbeddingService

    init(db: DatabaseQueue, embedder: EmbeddingService) {
        self.db = db
        self.embedder = embedder
    }

    // MARK: - CRUD

    func create(name: String, description: String?, sourceType: String, sourcePath: String?) throws -> KnowledgeBase {
        let kb = KnowledgeBase(name: name, description: description, sourceType: sourceType, sourcePath: sourcePath)
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO knowledge_bases (id, name, description, sourceType, sourcePath, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [kb.id, kb.name, kb.description, kb.sourceType, kb.sourcePath, kb.createdAt, kb.updatedAt])
        }
        return kb
    }

    func getAll() throws -> [KnowledgeBase] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, name, description, sourceType, sourcePath, createdAt, updatedAt FROM knowledge_bases ORDER BY updatedAt DESC")
            return rows.map { row in
                let id: String = row["id"]
                let name: String = row["name"]
                let desc: String? = row["description"]
                let st: String = row["sourceType"]
                let sp: String? = row["sourcePath"]
                let ca: TimeInterval = row["createdAt"]
                let ua: TimeInterval = row["updatedAt"]
                return KnowledgeBase(id: id, name: name, description: desc, sourceType: st, sourcePath: sp, createdAt: ca, updatedAt: ua)
            }
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM knowledge_items WHERE knowledgeBaseId = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM knowledge_bases WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Ingestion

    func ingest(id: String, progress: ((String) -> Void)? = nil) async throws {
        guard let kb = try getById(id) else { return }
        progress?("Starting ingestion for \(kb.name)...")

        try await db.write { db in
            try db.execute(sql: "DELETE FROM knowledge_items WHERE knowledgeBaseId = ?", arguments: [id])
        }

        switch kb.sourceType {
        case "file":
            if let path = kb.sourcePath {
                try await indexFile(path: path, kbId: id, progress: progress)
            }
        case "folder":
            if let path = kb.sourcePath {
                try await indexFolder(path: path, kbId: id, progress: progress)
            }
        case "repo":
            if let url = kb.sourcePath {
                let localPath = try await cloneOrPullRepo(url: url, kbId: id, progress: progress)
                try await indexFolder(path: localPath, kbId: id, progress: progress)
            }
        case "url":
            if let urlStr = kb.sourcePath, let url = URL(string: urlStr) {
                try await indexURL(url: url, kbId: id, progress: progress)
            }
        default:
            break
        }

        try await db.write { db in
            try db.execute(sql: "UPDATE knowledge_bases SET updatedAt = ? WHERE id = ?", arguments: [Date().timeIntervalSince1970, id])
        }
        progress?("Ingestion complete.")
    }

    private func indexFile(path: String, kbId: String, progress: ((String) -> Void)? = nil) async throws {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            progress?("Skipping unsupported file: \(path)")
            return
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let chunks = chunkContent(content, chunkSize: 512, overlap: 64)
        progress?("Indexing \(url.lastPathComponent) (\(chunks.count) chunks)...")
        for (i, chunk) in chunks.enumerated() {
            let embedding = try? await embedder.embed(text: String(chunk.prefix(8000)))
            try storeChunk(kbId: kbId, filePath: path, chunkIndex: i, content: chunk, embedding: embedding)
        }
    }

    private func indexFolder(path: String, kbId: String, progress: ((String) -> Void)? = nil) async throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return }
        var files: [String] = []
        for case let file as String in enumerator {
            let ext = (file as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let fullPath = (path as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
            files.append(fullPath)
        }
        files.sort()
        progress?("Found \(files.count) files to index")
        for (idx, file) in files.enumerated() {
            progress?("[\(idx + 1)/\(files.count)] \(URL(fileURLWithPath: file).lastPathComponent)")
            try await indexFile(path: file, kbId: kbId)
        }
    }

    private func cloneOrPullRepo(url: String, kbId: String, progress: ((String) -> Void)? = nil) async throws -> String {
        let repoDir = repoCachePath(for: url)
        let fm = FileManager.default
        if fm.fileExists(atPath: repoDir) {
            progress?("Pulling latest changes for repo...")
            try runGit(in: repoDir, args: ["pull"])
        } else {
            progress?("Cloning repo...")
            try fm.createDirectory(at: URL(fileURLWithPath: repoDir).deletingLastPathComponent(), withIntermediateDirectories: true)
            try runGit(in: repoDir, args: ["clone", url, repoDir])
        }
        return repoDir
    }

    private func indexURL(url: URL, kbId: String, progress: ((String) -> Void)? = nil) async throws {
        progress?("Fetching URL: \(url.absoluteString)")
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let html = String(data: data, encoding: .utf8) else { return }
        let text = extractText(from: html)
        let chunks = chunkContent(text, chunkSize: 512, overlap: 64)
        progress?("Indexing \(chunks.count) chunks from web page...")
        for (i, chunk) in chunks.enumerated() {
            let embedding = try? await embedder.embed(text: String(chunk.prefix(8000)))
            try storeChunk(kbId: kbId, filePath: url.absoluteString, chunkIndex: i, content: chunk, embedding: embedding)
        }
    }

    // MARK: - Search

    func search(query: String, kbIds: [String], limit: Int = 10) async throws -> [(KnowledgeItem, Float)] {
        guard !kbIds.isEmpty else { return [] }
        let queryEmbedding = try await embedder.embed(text: query)
        let placeholders = kbIds.map { _ in "?" }.joined(separator: ",")
        let maxFetch = min(limit * 10, 200)
        let rows = try await db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, knowledgeBaseId, filePath, chunkIndex, content, createdAt
                FROM knowledge_items
                WHERE knowledgeBaseId IN (\(placeholders))
                ORDER BY createdAt DESC
                LIMIT ?
            """, arguments: StatementArguments(kbIds) + [maxFetch])
        }

        var items: [(KnowledgeItem, [Float])] = []
        for row in rows {
            let id: String = row["id"]
            let kbId: String = row["knowledgeBaseId"]
            let fp: String? = row["filePath"]
            guard let ci64: Int64 = row["chunkIndex"] else { continue }
            let ci = Int(ci64)
            let content: String = row["content"]
            let ca: TimeInterval = row["createdAt"]
            let item = KnowledgeItem(id: id, knowledgeBaseId: kbId, filePath: fp, chunkIndex: ci, content: content, createdAt: ca)
            if let blob: Data = row["embedding"], !blob.isEmpty {
                let emb = blob.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                items.append((item, emb))
            } else {
                items.append((item, []))
            }
        }

        let results = items.compactMap { (item, emb) -> (KnowledgeItem, Float)? in
            guard !emb.isEmpty else { return (item, 0) }
            return (item, cosineSimilarity(queryEmbedding, emb))
        }

        return results.sorted { $0.1 > $1.1 }.prefix(limit).map { $0 }
    }

    // MARK: - Helpers

    private func getById(_ id: String) throws -> KnowledgeBase? {
        try db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT id, name, description, sourceType, sourcePath, createdAt, updatedAt FROM knowledge_bases WHERE id = ?", arguments: [id])
            guard let row else { return nil }
            let id: String = row["id"]
            let name: String = row["name"]
            let desc: String? = row["description"]
            let st: String = row["sourceType"]
            let sp: String? = row["sourcePath"]
            let ca: TimeInterval = row["createdAt"]
            let ua: TimeInterval = row["updatedAt"]
            return KnowledgeBase(id: id, name: name, description: desc, sourceType: st, sourcePath: sp, createdAt: ca, updatedAt: ua)
        }
    }

    private func storeChunk(kbId: String, filePath: String?, chunkIndex: Int, content: String, embedding: [Float]?) throws {
        let data = embedding?.withUnsafeBufferPointer { Data(buffer: $0) }
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO knowledge_items (id, knowledgeBaseId, filePath, chunkIndex, content, embedding, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [UUID().uuidString, kbId, filePath, chunkIndex, content, data, Date().timeIntervalSince1970])
        }
    }

    private func chunkContent(_ content: String, chunkSize: Int = 512, overlap: Int = 64) -> [String] {
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

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let normA = sqrt(a.reduce(0) { $0 + $1 * $1 })
        let normB = sqrt(b.reduce(0) { $0 + $1 * $1 })
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA * normB)
    }

    private func runGit(in path: String, args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        try process.run()
        process.waitUntilExit()
    }

    private func repoCachePath(for url: String) -> String {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let repoDir = caches.appendingPathComponent("com.orbit").appendingPathComponent("repos")
        let name = url
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return repoDir.appendingPathComponent(name).path
    }

    private func extractText(from html: String) -> String {
        guard let data = html.data(using: .utf8),
              let doc = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil)
        else { return html }
        return doc.string
    }
}
