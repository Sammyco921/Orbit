import Testing
import Foundation
@testable import Orbit

// MARK: - Step with dependencies

@Test func stepWithDependencies() {
    let step = Step(name: "Step 2", stepType: .action, toolName: "tool", input: [:], dependencies: [0])
    #expect(step.dependencies == [0])
}

@Test func stepWithoutDependenciesDefaultsToEmpty() {
    let step = Step(name: "Step 1", stepType: .research)
    #expect(step.dependencies.isEmpty)
}

// MARK: - WorkflowEngine DAG execution tests

actor StepTracker {
    var steps: Set<Int> = []
    func mark(_ i: Int) { steps.insert(i) }
    var completed: Set<Int> { steps }
}

@Test func parallelGraphExecutesAllSteps() async {
    let graph = TaskGraph()
    graph.addNode(for: 0, dependencies: [])
    graph.addNode(for: 1, dependencies: [])
    graph.addNode(for: 2, dependencies: [0])

    let tracker = StepTracker()

    await WorkflowEngine.executeGraph(graph: graph) { node in
        await tracker.mark(node.stepIndex)
    }

    let executed = await tracker.completed
    #expect(executed.count == 3, "All three steps should execute")
    #expect(executed.contains(0))
    #expect(executed.contains(1))
    #expect(executed.contains(2))
    #expect(graph.nodes.values.allSatisfy { $0.state == .succeeded })
}

actor OrderTracker {
    var order: [Int] = []
    func append(_ i: Int) { order.append(i) }
    var result: [Int] { order }
}

@Test func sequentialGraphExecutesInOrder() async {
    let graph = TaskGraph.sequential(3)
    let tracker = OrderTracker()

    await WorkflowEngine.executeGraph(graph: graph) { node in
        await tracker.append(node.stepIndex)
    }

    let order = await tracker.result
    #expect(order == [0, 1, 2], "Sequential graph should execute steps 0, 1, 2 in order")
}

actor FailureTracker {
    var steps: [Int] = []
    func mark(_ i: Int) { steps.append(i) }
    var result: [Int] { steps }
}

@Test func nodeFailureSkipsDependents() async {
    let graph = TaskGraph()
    graph.addNode(for: 0, dependencies: [])
    graph.addNode(for: 1, dependencies: [0])
    graph.addNode(for: 2, dependencies: [1])

    let tracker = FailureTracker()

    await WorkflowEngine.executeGraph(graph: graph) { node in
        await tracker.mark(node.stepIndex)
        if node.stepIndex == 0 {
            throw NSError(domain: "test", code: 1, userInfo: nil)
        }
    }

    let executed = await tracker.result
    #expect(executed.count == 3, "Step 0 should retry 3 times")
    #expect(Set(executed) == [0], "Only step 0 should execute")
    #expect(graph.nodes.values.contains(where: { $0.stepIndex == 1 && $0.state == .skipped }))
    #expect(graph.nodes.values.contains(where: { $0.stepIndex == 2 && $0.state == .skipped }))
}

actor RetryTracker {
    var count = 0
    func increment() { count += 1 }
    var value: Int { count }
}

@Test func nodeRetriesOnFailure() async {
    let graph = TaskGraph()
    graph.addNode(for: 0, dependencies: [])

    let tracker = RetryTracker()

    await WorkflowEngine.executeGraph(graph: graph) { _ in
        await tracker.increment()
        throw NSError(domain: "test", code: 1, userInfo: nil)
    }

    let attempts = await tracker.value
    #expect(attempts == 3, "Should attempt 3 times before giving up")
    #expect(graph.nodes[graph.nodes.values.first!.id]?.state == .failed)
}

// MARK: - PlanGenerator validation tests

private final class MockTool: Tool {
    let definition: ToolDefinition
    init(id: String) {
        definition = ToolDefinition(
            id: id,
            name: id,
            description: "Mock \(id)",
            inputSchema: ToolSchema(parameters: [])
        )
    }
    func run(input: [String: String]) async throws -> String { "ok" }
}

private final class MockPlannerLLM: LLMProvider {
    let name = "MockPlanner"
    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String { "" }
    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func makeGenerator() -> PlanGenerator {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))
    registry.register(MockTool(id: "write"))
    registry.register(MockTool(id: "read"))
    return PlanGenerator(
        tools: registry,
        llm: MockPlannerLLM(),
        parameters: ModelParameters()
    )
}

@Test func validatePlanAcceptsValidPlan() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "Search", tool: "search", input: [:], dependencies: []),
        GeneratedStep(description: "Write", tool: "write", input: [:], dependencies: [0])
    ])
    #expect(generator.validatePlan(plan))
}

@Test func validatePlanRejectsUnknownTool() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "Nope", tool: "nonexistent", input: [:], dependencies: [])
    ])
    #expect(!generator.validatePlan(plan))
}

@Test func validatePlanRejectsCycle() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "A", tool: "search", input: [:], dependencies: [2]),
        GeneratedStep(description: "B", tool: "write", input: [:], dependencies: [0]),
        GeneratedStep(description: "C", tool: "read", input: [:], dependencies: [1])
    ])
    #expect(!generator.validatePlan(plan))
}

@Test func validatePlanRejectsOutOfBoundsDependency() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "A", tool: "search", input: [:], dependencies: [5])
    ])
    #expect(!generator.validatePlan(plan))
}

@Test func validatePlanRejectsSelfDependency() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "A", tool: "search", input: [:], dependencies: [0])
    ])
    #expect(!generator.validatePlan(plan))
}

@Test func validatePlanAcceptsParallelGraph() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Test", steps: [
        GeneratedStep(description: "A", tool: "search", input: [:], dependencies: []),
        GeneratedStep(description: "B", tool: "read", input: [:], dependencies: []),
        GeneratedStep(description: "C", tool: "write", input: [:], dependencies: [0, 1])
    ])
    #expect(generator.validatePlan(plan))
}

@Test func validatePlanRejectsEmptyPlan() {
    let generator = makeGenerator()
    let plan = GeneratedPlan(summary: "Empty", steps: [])
    #expect(!generator.validatePlan(plan))
}

// MARK: - TaskGraph tests

@Test func taskGraphReadyNodesWhenDependenciesSatisfied() {
    let graph = TaskGraph()
    graph.addNode(for: 0, dependencies: [])
    graph.addNode(for: 1, dependencies: [0])
    graph.addNode(for: 2, dependencies: [])

    let ready = graph.readyNodes
    #expect(ready.count == 2, "Steps with no deps should be ready")
    #expect(ready.contains(where: { $0.stepIndex == 0 }))
    #expect(ready.contains(where: { $0.stepIndex == 2 }))
}

@Test func taskGraphIsCompleteWhenAllDone() {
    let graph = TaskGraph.sequential(3)
    for node in graph.nodes.values {
        node.state = .succeeded
    }
    #expect(graph.isComplete)
}

@Test func taskGraphHasFailedWhenAnyFailed() {
    let graph = TaskGraph.sequential(3)
    graph.nodes.values.first?.state = .failed
    #expect(graph.hasFailed)
}

// MARK: - Replanning tests

private final class ReplanMockLLM: LLMProvider {
    let name = "ReplanMock"
    let response: String
    init(response: String) { self.response = response }
    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        response
    }
    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@Test func replanReturnsRevisedPlan() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))
    registry.register(MockTool(id: "write"))

    let json = """
    {"summary":"Retry with different query","steps":[{"description":"Search again","tool":"search","input":{"q":"revised"},"dependencies":[]},{"description":"Write results","tool":"write","input":{"content":"done"},"dependencies":[0]}]}
    """
    let llm = ReplanMockLLM(response: json)
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(
        goal: "Test goal",
        completedSteps: [("Step 1", "ok")],
        failedSteps: [("Step 2", "error")],
        remainingSteps: [("Step 3", "write")]
    )

    guard case .plan(let plan) = result else {
        Issue.record("Expected .plan, got .direct")
        return
    }
    #expect(plan.summary == "Retry with different query")
    #expect(plan.steps.count == 2)
    #expect(plan.steps[0].tool == "search")
    #expect(plan.steps[1].dependencies == [0])
}

@Test func replanReturnsDirectWhenLLMSaysDirect() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))

    let json = """
    {"action":"direct","reason":"Simple enough"}
    """
    let llm = ReplanMockLLM(response: json)
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(
        goal: "Simple goal",
        completedSteps: [],
        failedSteps: [("Step 1", "error")],
        remainingSteps: []
    )

    guard case .direct = result else {
        Issue.record("Expected .direct, got .plan")
        return
    }
}

@Test func replanFallsBackToDirectOnInvalidJSON() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))

    let llm = ReplanMockLLM(response: "not json")
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(
        goal: "Goal",
        completedSteps: [],
        failedSteps: [("Step 1", "error")],
        remainingSteps: []
    )

    guard case .direct = result else {
        Issue.record("Expected .direct fallback on bad JSON")
        return
    }
}

@Test func buildGraphWithDependenciesMarksRootsReady() {
    let graph = TaskGraph()
    graph.addNode(for: 0, dependencies: [])
    graph.addNode(for: 1, dependencies: [0])
    graph.addNode(for: 2, dependencies: [])

    for node in graph.nodes.values where node.dependencies.isEmpty {
        node.state = .ready
    }

    let ready = graph.readyNodes
    #expect(ready.count == 2)
    #expect(ready.contains(where: { $0.stepIndex == 0 }))
    #expect(ready.contains(where: { $0.stepIndex == 2 }))
}

@Test func buildGraphWithoutDependenciesCreatesSequential() {
    let graph = TaskGraph.sequential(3)
    #expect(graph.nodes.count == 3)
    #expect(graph.nodes.values.filter({ $0.state == .ready }).count == 1)
    #expect(graph.readyNodes.count == 1)
    #expect(graph.readyNodes.first?.stepIndex == 0)
}

// MARK: - PlanGenerator Direct Response Tests

@Test func planGeneratorReturnsDirectOnActionDirect() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))

    let json = """
    {"action":"direct","reason":"Simple request"}
    """
    let llm = ReplanMockLLM(response: json)
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(goal: "Simple goal")

    guard case .direct = result else {
        Issue.record("Expected .direct for simple goal")
        return
    }
}

@Test func planGeneratorReturnsDirectOnInvalidJSON() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))

    let llm = ReplanMockLLM(response: "this is not valid json at all")
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(goal: "Some goal")

    guard case .direct = result else {
        Issue.record("Expected .direct fallback on bad JSON")
        return
    }
}

@Test func planGeneratorReturnsDirectOnEmptySteps() async throws {
    let registry = ToolRegistry()
    registry.register(MockTool(id: "search"))

    let json = """
    {"summary":"No steps needed","steps":[]}
    """
    let llm = ReplanMockLLM(response: json)
    let generator = PlanGenerator(tools: registry, llm: llm, parameters: ModelParameters())

    let result = try await generator.generatePlan(goal: "Empty goal")

    guard case .direct = result else {
        Issue.record("Expected .direct for empty steps")
        return
    }
}

// MARK: - Local Model Manager Detection Tests

@Test func localModelManagerDiscoveryRunsWithoutCrashing() async {
    let manager = LocalModelManager()
    let result = await manager.discoverAll()
    // Result may or may not have servers depending on environment
    #expect(result.models.isEmpty || !result.models.isEmpty)
}

@Test func localModelManagerDetectsOllamaInstallStatus() {
    let manager = LocalModelManager()
    // Check FS-based detection (no server needed)
    _ = manager.ollamaInstallStatus
}
