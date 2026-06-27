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
            let msg = callCount < responses.count ? responses[callCount] : ""
            callCount += 1
            for char in msg {
                continuation.yield(String(char))
            }
            continuation.finish()
        }
    }
}

private final class GreetingTool: Tool {
    let definition = ToolDefinition(
        id: "greet",
        name: "Greeting",
        description: "Returns a greeting",
        inputSchema: ToolSchema(parameters: [ToolParameter(name: "name", description: "Name to greet", type: .string, required: true)])
    )

    func run(input: [String: String]) async throws -> String {
        let name = input["name"] ?? "World"
        return "Hello, \(name)!"
    }
}

private func createTestEngine() -> WorkflowEngine {
    let db = try! DatabaseQueue()
    let store = WorkflowStore(db: db)
    let audit = AuditService(db: db)
    let ts = ToolService(eventBus: EventBus(), screenUnderstandingService: ScreenUnderstandingService(), auditService: audit)
    return WorkflowEngine(store: store, toolService: ts)
}

// MARK: - executeStep Tests

@Test func executeStepActionRunsTool() async throws {
    let engine = createTestEngine()
    let tool = GreetingTool()
    engine.toolService.toolRegistry.register(tool)

    var step = Step(name: "Greet", stepType: .action, toolName: "greet", input: ["name": "Orbit"])
    var artifacts: [Artifact] = []
    let services = StepServices()

    try await engine.executeStep(&step, services: services, artifacts: &artifacts)

    #expect(step.result?.contains("Hello, Orbit!") == true)
}

@Test func executeStepActionToolNotFound() async {
    let engine = createTestEngine()
    var step = Step(name: "Missing", stepType: .action, toolName: "nonexistent", input: [:])
    var artifacts: [Artifact] = []
    let services = StepServices()

    await #expect(throws: OrbitError.toolNotFound("nonexistent")) {
        try await engine.executeStep(&step, services: services, artifacts: &artifacts)
    }
}


@Test func executeStepLLMUsesProvider() async throws {
    let engine = createTestEngine()
    let mockLLM = MockLLM()
    mockLLM.responses = ["Hello from LLM"]

    var tokens: [String] = []
    var step = Step(name: "Say hello", stepType: .llm)
    var artifacts: [Artifact] = []
    let services = StepServices(
        llmProvider: mockLLM,
        llmParameters: ModelParameters(),
        onToken: { tokens.append($0) }
    )

    try await engine.executeStep(&step, services: services, artifacts: &artifacts)

    #expect(tokens.joined().contains("Hello from LLM"))
}

@Test func executeStepLLMRequiresProvider() async {
    let engine = createTestEngine()
    var step = Step(name: "No LLM", stepType: .llm)
    var artifacts: [Artifact] = []
    let services = StepServices()

    await #expect(throws: OrbitError.stepFailed("No LLM", "LLM step requires LLM provider")) {
        try await engine.executeStep(&step, services: services, artifacts: &artifacts)
    }
}

@Test func executeStepResearchRequiresServices() async {
    let engine = createTestEngine()
    var step = Step(name: "Research", stepType: .research)
    var artifacts: [Artifact] = []
    let services = StepServices()

    await #expect(throws: OrbitError.stepFailed("Research", "Research requires ResearchService and LLM provider")) {
        try await engine.executeStep(&step, services: services, artifacts: &artifacts)
    }
}

@Test func executeStepGenerateRequiresServices() async {
    let engine = createTestEngine()
    var step = Step(name: "Generate", stepType: .generate)
    var artifacts: [Artifact] = []
    let services = StepServices()

    await #expect(throws: OrbitError.stepFailed("Generate", "Generate requires DocumentService and LLM provider")) {
        try await engine.executeStep(&step, services: services, artifacts: &artifacts)
    }
}

// MARK: - executeDAG Tests

@Test func executeDAGExecutesStepsInOrder() async throws {
    let engine = createTestEngine()
    let tool = GreetingTool()
    engine.toolService.toolRegistry.register(tool)

    var steps: [Step] = [
        Step(name: "Step 0", stepType: .action, toolName: "greet", input: ["name": "A"]),
        Step(name: "Step 1", stepType: .action, toolName: "greet", input: ["name": "B"], dependencies: [0]),
        Step(name: "Step 2", stepType: .action, toolName: "greet", input: ["name": "C"], dependencies: [1])
    ]
    var artifacts: [Artifact] = []
    let services = StepServices()

    let failed = await engine.executeDAG(
        stepCount: 3,
        dependencies: [[], [0], [1]],
        steps: &steps,
        services: services,
        artifacts: &artifacts
    )

    #expect(failed.isEmpty)
    #expect(steps[0].result?.contains("Hello, A!") == true)
    #expect(steps[1].result?.contains("Hello, B!") == true)
    #expect(steps[2].result?.contains("Hello, C!") == true)
}

@Test func executeDAGParallelSteps() async throws {
    let engine = createTestEngine()
    let tool = GreetingTool()
    engine.toolService.toolRegistry.register(tool)

    var steps: [Step] = [
        Step(name: "Step 0", stepType: .action, toolName: "greet", input: ["name": "A"]),
        Step(name: "Step 1", stepType: .action, toolName: "greet", input: ["name": "B"]),
        Step(name: "Step 2", stepType: .action, toolName: "greet", input: ["name": "C"], dependencies: [0, 1])
    ]
    var artifacts: [Artifact] = []
    let services = StepServices()

    let failed = await engine.executeDAG(
        stepCount: 3,
        dependencies: [[], [], [0, 1]],
        steps: &steps,
        services: services,
        artifacts: &artifacts
    )

    #expect(failed.isEmpty)
    #expect(steps[0].result?.contains("Hello, A!") == true)
    #expect(steps[1].result?.contains("Hello, B!") == true)
    #expect(steps[2].result?.contains("Hello, C!") == true)
}

// MARK: - executeReAct Tests

@Test func executeReActBasicLoop() async throws {
    let engine = createTestEngine()
    let tool = GreetingTool()
    engine.toolService.toolRegistry.register(tool)

    let mockLLM = MockLLM()
    mockLLM.responses = [
        #"{"action":"tool","tool":"greet","input":{"name":"Orbit"}}"#,
        #"{"action":"complete","summary":"Greeted Orbit"}"#
    ]

    let manager = try makeCheckpointManager()

    let stream = engine.executeReAct(
        goalDescription: "Test ReAct",
        maxSteps: 10,
        contextMessages: [LLMMessage(role: .user, content: "Say hello")],
        llm: mockLLM,
        tools: engine.toolService.toolRegistry,
        parameters: ModelParameters(),
        checkpointManager: manager,
        executionId: "react-test-1",
        conversationId: nil,
        approvalMode: .autoApprove
    )

    var events: [AgentEvent] = []
    for await event in stream {
        events.append(event)
        if case .completed = event { break }
    }

    let toolExecs = events.filter {
        if case .toolExecution = $0 { return true }
        return false
    }
    #expect(toolExecs.count == 1, "Should execute one tool")

    let completed = events.filter {
        if case .completed(let summary) = $0, summary.contains("Greeted") { return true }
        return false
    }
    #expect(!completed.isEmpty, "Should complete with summary")
}

@Test func executeReActMaxStepsRespected() async throws {
    let engine = createTestEngine()
    let tool = GreetingTool()
    engine.toolService.toolRegistry.register(tool)

    let mockLLM = MockLLM()
    mockLLM.responses = Array(repeating: #"{"action":"tool","tool":"greet","input":{"name":"loop"}}"#, count: 5)

    let manager = try makeCheckpointManager()

    let stream = engine.executeReAct(
        goalDescription: "Loop test",
        maxSteps: 3,
        contextMessages: [LLMMessage(role: .user, content: "Go")],
        llm: mockLLM,
        tools: engine.toolService.toolRegistry,
        parameters: ModelParameters(),
        checkpointManager: manager,
        executionId: "react-loop-test",
        conversationId: nil,
        approvalMode: .autoApprove
    )

    var toolCount = 0
    for await event in stream {
        if case .toolExecution = event {
            toolCount += 1
        }
        if case .completed = event { break }
    }

    #expect(toolCount <= 3, "Should not exceed maxSteps")
}

// MARK: - Helpers

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
