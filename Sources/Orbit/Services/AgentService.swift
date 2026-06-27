import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "agent")

final class AgentService {
    private let toolService: ToolService
    private let memoryService: MemoryService
    private let workflowEngine: WorkflowEngine
    private(set) var checkpointManager: CheckpointManager?

    init(toolService: ToolService, memoryService: MemoryService, workflowEngine: WorkflowEngine) {
        self.toolService = toolService
        self.memoryService = memoryService
        self.workflowEngine = workflowEngine
    }

    func configure(checkpointManager: CheckpointManager) {
        self.checkpointManager = checkpointManager
    }

    func execute(
        goalDescription: String,
        maxSteps: Int = 25,
        llm: LLMProvider,
        parameters: ModelParameters,
        contextMessages: [LLMMessage],
        approvalMode: ApprovalMode = .interactive
    ) -> AsyncStream<AgentEvent> {
        workflowEngine.executeReAct(
            goalDescription: goalDescription,
            maxSteps: maxSteps,
            contextMessages: contextMessages,
            llm: llm,
            tools: toolService.toolRegistry,
            parameters: parameters,
            checkpointManager: checkpointManager,
            executionId: UUID().uuidString,
            conversationId: nil,
            approvalMode: approvalMode
        )
    }

    func resume(
        from checkpoint: ExecutionCheckpoint,
        llm: LLMProvider,
        parameters: ModelParameters,
        approvalMode: ApprovalMode = .interactive
    ) -> AsyncStream<AgentEvent> {
        var contextMessages = checkpoint.messages
        if contextMessages.first?.role == .system {
            contextMessages = Array(contextMessages.dropFirst())
        }

        return workflowEngine.executeReAct(
            goalDescription: checkpoint.goalDescription,
            maxSteps: 25,
            contextMessages: contextMessages,
            llm: llm,
            tools: toolService.toolRegistry,
            parameters: parameters,
            checkpointManager: checkpointManager,
            executionId: checkpoint.id,
            conversationId: checkpoint.conversationId,
            approvalMode: approvalMode,
            initialStepCount: checkpoint.stepCount,
            initialToolFailures: checkpoint.toolFailures
        )
    }
}
