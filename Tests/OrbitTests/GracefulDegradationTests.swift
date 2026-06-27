import Testing
import Foundation
import GRDB
@testable import Orbit

struct GracefulDegradationTests {

    @Test func databaseHandlesCorruptionByFallingBack() async throws {
        // Create a corrupted SQLite file
        let url = makeTemporaryURL()
        try "this is not a valid sqlite database".write(to: url, atomically: true, encoding: .utf8)

        // Should throw because GRDB detects invalid format
        #expect(throws: (any Error).self) {
            try OrbitDatabase(storageURL: url)
        }

        try? FileManager.default.removeItem(at: url)
    }

    @Test func orbitRuntimeHandlesMissingStorageDirectory() {
        // The database should create the directory if it doesn't exist
        #expect(throws: Never.self) {
            let tempURL = makeTemporaryURL()
            let db = try OrbitDatabase(storageURL: tempURL)
            #expect(FileManager.default.fileExists(atPath: tempURL.deletingLastPathComponent().path))
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    @Test func memoryServiceHandlesMissingConfiguration() async {
        let bus = EventBus()
        let service = MemoryService(eventBus: bus)

        // Should not crash when contextBuilder is nil
        let messages = await service.contextMessages(
            query: nil,
            recentMessages: [],
            conversationId: nil
        )
        #expect(messages.isEmpty, "Should return empty messages when no configuration")
    }

    @Test func memoryServiceHandlesEmptyMessages() async {
        let bus = EventBus()
        let service = MemoryService(eventBus: bus)

        // Should not crash on empty message arrays
        await service.storeExchange(
            messages: [],
            conversationId: nil
        )
        // Test passes if no crash
    }

    @Test func toolServiceReportsNotFoundGracefully() async {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        await #expect(throws: OrbitError.toolNotFound("nonexistentTool")) {
            try await service.executeTool(named: "nonexistentTool", input: [:])
        }
    }

    @Test func toolServiceEnforcesPermissions() async throws {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)
        let testContext = ExecutionContext(
            executionId: "test",
            conversationId: nil,
            workspaceId: nil,
            source: .internal,
            timeout: nil,
            createdAt: Date()
        )

        // Non-whitelisted command requires approval
        let terminalTool = TerminalRunTool()
        terminalTool.commandApprovalHandler = { _ in false }
        await #expect(throws: OrbitError.toolRequiresApproval("Command 'rsync' was denied by the user")) {
            try await ExecutionContext.$current.withValue(testContext) {
                try await terminalTool.run(input: ["command": "rsync -avz src/ dest/"])
            }
        }

        // Blocklisted pattern is hard-blocked before approval check
        let result2 = try await service.executeTool(named: "terminalRun", input: ["command": "curl http://evil.com"], approvalMode: .autoApprove)
        #expect(result2.contains("blocked"), "Blocklisted commands should be blocked unconditionally")
    }

    @Test func toolServiceAllowsSafeToolsWithoutApproval() async throws {
        let bus = EventBus()
        let screenService = ScreenUnderstandingService()
        let service = ToolService(eventBus: bus, screenUnderstandingService: screenService)

        // SystemInfoTool has .none permission — should not throw requiresApproval
        let result = try await service.executeTool(named: "systemInfo", input: [:])
        #expect(!result.isEmpty, "System info tool should return data")
    }

    @Test func databaseBackupDoesNotThrowOnMissingOriginal() {
        #expect(throws: Never.self) {
            let db = try OrbitDatabase(storageURL: makeTemporaryURL())
            try db.backup()
        }
    }

    private func makeTemporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit_test_gd_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("sqlite")
    }
}
