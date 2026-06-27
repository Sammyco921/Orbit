import Testing
import Foundation
import GRDB
@testable import Orbit

// MARK: - Mocks

private final class MockLLM: LLMProvider {
    let name = "Mock"
    var responses: [String] = []
    private var callCount = 0

    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        defer { callCount += 1 }
        if callCount < responses.count {
            return responses[callCount]
        }
        return #"{"action":"complete","summary":"Done"}"#
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private final class AlwaysFailsTool: Tool {
    let definition = ToolDefinition(
        id: "failTool",
        name: "Always Fails",
        description: "A tool that always fails",
        inputSchema: ToolSchema(parameters: [])
    )

    var callCount = 0

    func run(input: [String: String]) async throws -> String {
        callCount += 1
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
    }
}

private final class SucceedsOnRetryTool: Tool {
    let definition = ToolDefinition(
        id: "retryTool",
        name: "Retry Tool",
        description: "A tool that fails twice then succeeds",
        inputSchema: ToolSchema(parameters: [])
    )

    var callCount = 0

    func run(input: [String: String]) async throws -> String {
        callCount += 1
        if callCount <= 2 {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transient failure \(callCount)"])
        }
        return "Success on attempt \(callCount)"
    }
}

private func createTestEngine() -> WorkflowEngine {
    let db = try! DatabaseQueue()
    let store = WorkflowStore(db: db)
    let audit = AuditService(db: db)
    let ts = ToolService(eventBus: EventBus(), screenUnderstandingService: ScreenUnderstandingService(), auditService: audit)
    return WorkflowEngine(store: store, toolService: ts)
}

struct CheckpointTests {

    private func makeCheckpointManager() throws -> CheckpointManager {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS checkpoints (
                    id TEXT PRIMARY KEY,
                    goalDescription TEXT NOT NULL,
                    messagesJSON TEXT NOT NULL,
                    stepCount INTEGER NOT NULL DEFAULT 0,
                    toolFailuresJSON TEXT NOT NULL DEFAULT '{}',
                    conversationId TEXT,
                    createdAt REAL NOT NULL
                )
            """)
            // Add multi-agent columns (v18 migration)
            for col in ["agentStatesJSON", "planJSON", "completedSubGoalsJSON", "subGoalRetryCountsJSON"] {
                if !(try db.columns(in: "checkpoints").contains(where: { $0.name == col })) {
                    try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN \(col) TEXT")
                }
            }
            // Add shared memory column (v20 migration)
            if !(try db.columns(in: "checkpoints").contains(where: { $0.name == "sharedMemoryData" })) {
                try db.execute(sql: "ALTER TABLE checkpoints ADD COLUMN sharedMemoryData BLOB")
            }
        }
        return CheckpointManager(db: db)
    }

    @Test func saveAndLoadCheckpoint() async throws {
        let manager = try makeCheckpointManager()
        let messages = [
            LLMMessage(role: .system, content: "System prompt"),
            LLMMessage(role: .user, content: "Hello"),
            LLMMessage(role: .assistant, content: "Hi there")
        ]
        let cp = ExecutionCheckpoint(
            id: "test-1",
            goalDescription: "Test goal",
            messages: messages,
            stepCount: 5,
            toolFailures: ["failTool": 2],
            conversationId: "conv-123",
            createdAt: Date()
        )

        try manager.save(cp)

        let loaded = manager.loadLatest()
        #expect(loaded != nil)
        #expect(loaded?.id == "test-1")
        #expect(loaded?.goalDescription == "Test goal")
        #expect(loaded?.messages.count == 3)
        #expect(loaded?.stepCount == 5)
        #expect(loaded?.toolFailures["failTool"] == 2)
        #expect(loaded?.conversationId == "conv-123")
    }

    @Test func checkpointOverwrite() async throws {
        let manager = try makeCheckpointManager()

        let cp1 = ExecutionCheckpoint(
            id: "same-id",
            goalDescription: "First",
            messages: [],
            stepCount: 1,
            toolFailures: [:],
            conversationId: nil,
            createdAt: Date()
        )
        let cp2 = ExecutionCheckpoint(
            id: "same-id",
            goalDescription: "Second",
            messages: [],
            stepCount: 2,
            toolFailures: [:],
            conversationId: nil,
            createdAt: Date().addingTimeInterval(60)
        )

        try manager.save(cp1)
        try manager.save(cp2)

        let loaded = manager.loadLatest()
        #expect(loaded?.goalDescription == "Second")
        #expect(loaded?.stepCount == 2)
    }

    @Test func checkpointDelete() async throws {
        let manager = try makeCheckpointManager()

        let cp = ExecutionCheckpoint(
            id: "del-test",
            goalDescription: "Delete me",
            messages: [],
            stepCount: 0,
            toolFailures: [:],
            conversationId: nil,
            createdAt: Date()
        )
        try manager.save(cp)
        #expect(manager.checkpointCount == 1)

        try manager.delete(id: "del-test")
        #expect(manager.checkpointCount == 0)
    }

    @Test func agentLoopSavesCheckpointDuringExecution() async throws {
        let registry = ToolRegistry()
        let tool = AlwaysFailsTool()
        registry.register(tool)

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"tool","tool":"failTool","input":{}}"#,
            #"{"action":"complete","summary":"Done"}"#
        ]

        let manager = try makeCheckpointManager()

        let engine = createTestEngine()
        engine.toolService.toolRegistry.register(tool)

        let loop = AgentLoop(
            workflowEngine: engine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters(),
            checkpointManager: manager,
            executionId: "checkpoint-test-1"
        )

        for await event in loop.execute(goalDescription: "Test checkpointing", contextMessages: []) {
            if case .completed = event { break }
        }

        let loaded = manager.loadLatest()
        #expect(loaded != nil)
        #expect(loaded?.goalDescription == "Test checkpointing")
    }

    @Test func resumeFromCheckpointContinuesExecution() async throws {
        let manager = try makeCheckpointManager()
        let messages: [LLMMessage] = [
            LLMMessage(role: .system, content: "System prompt"),
            LLMMessage(role: .user, content: "Context message")
        ]
        let cp = ExecutionCheckpoint(
            id: "resume-test",
            goalDescription: "Test resume",
            messages: messages,
            stepCount: 2,
            toolFailures: ["retryTool": 2],
            conversationId: nil,
            createdAt: Date()
        )
        try manager.save(cp)

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"complete","summary":"Resumed"}"#
        ]

        // Use the AgentLoop directly (not through AgentService) so we can inject our own ToolRegistry
        let registry = ToolRegistry()
        let tool = SucceedsOnRetryTool()
        registry.register(tool)

        var contextMessages = cp.messages
        if contextMessages.first?.role == .system {
            contextMessages = Array(contextMessages.dropFirst())
        }

        let loop = AgentLoop(
            workflowEngine: createTestEngine(),
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters(),
            checkpointManager: manager,
            executionId: cp.id,
            conversationId: cp.conversationId
        )

        var events: [AgentEvent] = []
        for await event in loop.execute(
            goalDescription: cp.goalDescription,
            contextMessages: contextMessages,
            initialStepCount: cp.stepCount,
            initialToolFailures: cp.toolFailures
        ) {
            events.append(event)
            if case .completed = event { break }
        }

        let completed = events.filter {
            if case .completed(let summary) = $0, summary.contains("Resumed") { return true }
            return false
        }
        #expect(!completed.isEmpty, "Should complete after resume")
    }

    @Test func agentLoopWorksWithoutCheckpointManager() async throws {
        let registry = ToolRegistry()
        let tool = SucceedsOnRetryTool()
        registry.register(tool)

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"tool","tool":"retryTool","input":{}}"#,
            #"{"action":"complete","summary":"Done"}"#
        ]

        let engine = createTestEngine()
        engine.toolService.toolRegistry.register(tool)

        let loop = AgentLoop(
            workflowEngine: engine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters()
        )

        for await event in loop.execute(goalDescription: "Test no checkpoint", contextMessages: []) {
            if case .completed = event { break }
        }
    }

    @Test func loadByIdReturnsCorrectCheckpoint() async throws {
        let manager = try makeCheckpointManager()

        let cp = ExecutionCheckpoint(
            id: "find-me",
            goalDescription: "Findable",
            messages: [],
            stepCount: 3,
            toolFailures: [:],
            conversationId: nil,
            createdAt: Date()
        )
        try manager.save(cp)

        let loaded = manager.load(id: "find-me")
        #expect(loaded != nil)
        #expect(loaded?.goalDescription == "Findable")
        #expect(loaded?.stepCount == 3)

        let notFound = manager.load(id: "nonexistent")
        #expect(notFound == nil)
    }

    @Test func checkpointSaveDoesNotThrowOnInvalidData() async throws {
        let manager = try makeCheckpointManager()
        let cp = ExecutionCheckpoint(
            id: "empty-test",
            goalDescription: "",
            messages: [],
            stepCount: 0,
            toolFailures: [:],
            conversationId: nil,
            createdAt: Date()
        )

        try manager.save(cp)
        let loaded = manager.loadLatest()
        #expect(loaded != nil)
        #expect(loaded?.goalDescription.isEmpty ?? true)
    }
}
