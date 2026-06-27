import Testing
import Foundation
import GRDB
@testable import Orbit

struct DatabasePerformanceTests {

    @Test func bulkInsertAndSearchPerformance() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())

        // Insert 100 conversations with 50 messages each
        for i in 0..<100 {
            let conv = Conversation(title: "Performance Test \(i)")
            var messages: [Message] = []
            for j in 0..<50 {
                messages.append(Message(
                    role: j.isMultiple(of: 2) ? .user : .assistant,
                    content: "This is message \(j) in conversation \(i). The quick brown fox jumps over the lazy dog."
                ))
            }
            var mutableConv = conv
            mutableConv.messages = messages
            try db.saveConversation(mutableConv)
        }

        // Measure full-text search performance
        let query = "fox jumps"
        let start = CFAbsoluteTimeGetCurrent()

        let results = try db.searchConversations(query: query)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        #expect(!results.isEmpty, "Expected at least one conversation matching 'fox'")
        #expect(elapsed < 500, "Full-text search took \(elapsed)ms — expected < 500ms for 100 convs * 50 msgs")

        // Clean up
        try? FileManager.default.removeItem(at: OrbitDatabase.storageURL)
    }

    @Test func conversationLoadPerformance() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())

        // Insert 50 conversations
        for i in 0..<50 {
            let conv = Conversation(title: "Load Test \(i)")
            var messages: [Message] = []
            for j in 0..<20 {
                messages.append(Message(
                    role: j.isMultiple(of: 2) ? .user : .assistant,
                    content: "Sample message content \(j) for conversation \(i)"
                ))
            }
            var mutableConv = conv
            mutableConv.messages = messages
            try db.saveConversation(mutableConv)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let loaded = try db.loadAllConversations()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(loaded.count == 50, "Expected 50 conversations")
        #expect(elapsed < 500, "Loading 50 conversations took \(elapsed)ms — expected < 500ms")

        try? FileManager.default.removeItem(at: OrbitDatabase.storageURL)
    }

    @Test func integrityCheckOnHealthyDatabase() async throws {
        let db = try OrbitDatabase(storageURL: makeTemporaryURL())
        #expect(db.isDegraded == false, "Healthy database should pass integrity check")
        try? FileManager.default.removeItem(at: OrbitDatabase.storageURL)
    }

    @Test func backupAndRecovery() async throws {
        let url = makeTemporaryURL()
        let db = try OrbitDatabase(storageURL: url)

        let conv = Conversation(title: "Backup Test")
        var mutableConv = conv
        mutableConv.messages = [Message(role: .user, content: "Hello backup")]
        try db.saveConversation(mutableConv)

        try db.backup()

        // Verify backup exists
        let backupURL = OrbitDatabase.backupURL
        #expect(FileManager.default.fileExists(atPath: backupURL.path), "Backup file should exist")

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: backupURL)
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit_test_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("sqlite")
    }
}
