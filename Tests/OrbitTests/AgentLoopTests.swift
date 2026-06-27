import Testing
import Foundation
import GRDB
@testable import Orbit

// MARK: - Mock LLM Provider

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

// MARK: - Mock Tools

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

private final class SlowTool: Tool {
    let definition = ToolDefinition(
        id: "slowTool",
        name: "Slow Tool",
        description: "A tool that takes time",
        inputSchema: ToolSchema(parameters: [])
    )

    func run(input: [String: String]) async throws -> String {
        try await Task.sleep(nanoseconds: 100_000_000)
        return "Slow result"
    }
}

private func createTestEngine() -> WorkflowEngine {
    let db = try! DatabaseQueue()
    let store = WorkflowStore(db: db)
    let audit = AuditService(db: db)
    let ts = ToolService(eventBus: EventBus(), screenUnderstandingService: ScreenUnderstandingService(), auditService: audit)
    return WorkflowEngine(store: store, toolService: ts)
}

struct AgentLoopTests {
    let testEngine = createTestEngine()

    @Test func toolFailureTriggersSelfCorrection() async {
        let registry = ToolRegistry()
        let failTool = AlwaysFailsTool()
        registry.register(failTool)
        testEngine.toolService.toolRegistry.register(failTool)

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"tool","tool":"failTool","input":{}}"#,
            #"{"action":"complete","summary":"Gave up after tool failure"}"#
        ]

        let loop = AgentLoop(
            workflowEngine: testEngine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters()
        )

        var events: [AgentEvent] = []
        for await event in loop.execute(goalDescription: "Test self-correction", contextMessages: []) {
            events.append(event)
            if case .completed = event { break }
        }

        #expect(failTool.callCount <= 3, "Tool should not be called more than 3 times")
    }

    @Test func toolSucceedsAfterRetries() async {
        let registry = ToolRegistry()
        let retryTool = SucceedsOnRetryTool()
        registry.register(retryTool)
        testEngine.toolService.toolRegistry.register(retryTool)

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"tool","tool":"retryTool","input":{}}"#,
            #"{"action":"tool","tool":"retryTool","input":{}}"#,
            #"{"action":"tool","tool":"retryTool","input":{}}"#,
            #"{"action":"complete","summary":"Succeeded after retries"}"#
        ]

        let loop = AgentLoop(
            workflowEngine: testEngine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters()
        )

        var events: [AgentEvent] = []
        for await event in loop.execute(goalDescription: "Test retry", contextMessages: []) {
            events.append(event)
            if case .completed = event { break }
        }

        let successes = events.filter {
            if case .completed = $0 { return true }
            return false
        }
        #expect(!successes.isEmpty, "Goal should complete")
        #expect(retryTool.callCount == 3, "Tool should be called 3 times (fail, fail, succeed)")
    }

    @Test func unknownToolSendsErrorToLLM() async {
        let registry = ToolRegistry()

        let mockLLM = MockLLM()
        mockLLM.responses = [
            #"{"action":"tool","tool":"nonexistent","input":{}}"#,
            #"{"action":"complete","summary":"Done"}"#
        ]

        let loop = AgentLoop(
            workflowEngine: testEngine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters()
        )

        var events: [AgentEvent] = []
        for await event in loop.execute(goalDescription: "Test unknown tool", contextMessages: []) {
            events.append(event)
            if case .completed = event { break }
        }

        let errors = events.filter {
            if case .error(let msg) = $0, msg.contains("not found") { return true }
            return false
        }
        #expect(errors.isEmpty == false, "Should report tool not found error")
    }

    @Test func invalidJSONResponseIsHandled() async {
        let registry = ToolRegistry()

        let mockLLM = MockLLM()
        mockLLM.responses = [
            "This is not valid JSON",
            #"{"action":"complete","summary":"Recovered"}"#
        ]

        let loop = AgentLoop(
            workflowEngine: testEngine,
            llm: mockLLM,
            tools: registry,
            memoryStore: nil,
            embeddingService: nil,
            parameters: ModelParameters()
        )

        var events: [AgentEvent] = []
        for await event in loop.execute(goalDescription: "Test JSON parsing error", contextMessages: []) {
            events.append(event)
            if case .completed = event { break }
        }

        let completed = events.filter {
            if case .completed = $0 { return true }
            return false
        }
        #expect(!completed.isEmpty, "Should recover from invalid JSON")
    }
}
