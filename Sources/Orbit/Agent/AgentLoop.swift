import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "agent")

final class AgentLoop: Agent {
    private let workflowEngine: WorkflowEngine
    private let llm: LLMProvider
    private let tools: ToolRegistry
    private let memoryStore: MemoryStore?
    private let embeddingService: EmbeddingService?
    private let parameters: ModelParameters
    private let checkpointManager: CheckpointManager?
    private let executionId: String
    private let conversationId: String?
    private let approvalMode: ApprovalMode

    static func createForRuntime(runtime: OrbitRuntime, name: String) -> AgentLoop {
        AgentLoop(
            workflowEngine: runtime.workflowEngine,
            llm: runtime.llmService.currentProvider(),
            tools: runtime.toolService.toolRegistry,
            memoryStore: runtime.memoryService.memoryStore,
            embeddingService: runtime.memoryService.embeddingService,
            parameters: ModelParameters(),
            checkpointManager: runtime.checkpointManager,
            approvalMode: .interactive,
            name: name
        )
    }

    init(
        workflowEngine: WorkflowEngine,
        llm: LLMProvider,
        tools: ToolRegistry,
        memoryStore: MemoryStore?,
        embeddingService: EmbeddingService?,
        parameters: ModelParameters,
        checkpointManager: CheckpointManager? = nil,
        executionId: String = UUID().uuidString,
        conversationId: String? = nil,
        approvalMode: ApprovalMode = .interactive,
        name: String = "AgentLoop"
    ) {
        self.workflowEngine = workflowEngine
        self.llm = llm
        self.tools = tools
        self.memoryStore = memoryStore
        self.embeddingService = embeddingService
        self.parameters = parameters
        self.checkpointManager = checkpointManager
        self.executionId = executionId
        self.conversationId = conversationId
        self.approvalMode = approvalMode
        super.init(name: name, type: .executor)
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        var result = ""
        let messages = context.relevantMessages.map { LLMMessage(role: .user, content: $0) }
        for await event in workflowEngine.executeReAct(
            goalDescription: goal,
            maxSteps: 25,
            contextMessages: messages,
            llm: llm,
            tools: tools,
            parameters: parameters,
            checkpointManager: checkpointManager,
            executionId: executionId,
            conversationId: conversationId,
            approvalMode: approvalMode
        ) {
            if case .completed(let summary) = event {
                result = summary
                break
            }
        }
        return result
    }

    func execute(
        goalDescription: String,
        maxSteps: Int = 25,
        contextMessages: [LLMMessage],
        initialStepCount: Int = 0,
        initialToolFailures: [String: Int] = [:]
    ) -> AsyncStream<AgentEvent> {
        workflowEngine.executeReAct(
            goalDescription: goalDescription,
            maxSteps: maxSteps,
            contextMessages: contextMessages,
            llm: llm,
            tools: tools,
            parameters: parameters,
            checkpointManager: checkpointManager,
            executionId: executionId,
            conversationId: conversationId,
            approvalMode: approvalMode,
            initialStepCount: initialStepCount,
            initialToolFailures: initialToolFailures
        )
    }
}
