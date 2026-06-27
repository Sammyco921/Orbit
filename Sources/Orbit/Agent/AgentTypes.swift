import Foundation

/// Types of specialized agents
enum AgentType: String, Codable, CaseIterable, Sendable {
    case planner
    case executor
    case researcher
    case reviewer
    case memoryManager

    var displayName: String {
        switch self {
        case .planner: return "Planner"
        case .executor: return "Executor"
        case .researcher: return "Researcher"
        case .reviewer: return "Reviewer"
        case .memoryManager: return "Memory Manager"
        }
    }

    var icon: String {
        switch self {
        case .planner: return "flowchart"
        case .executor: return "wrench.and.screwdriver"
        case .researcher: return "magnifyingglass"
        case .reviewer: return "checkmark.seal"
        case .memoryManager: return "brain"
        }
    }
}

/// Lifecycle status of an agent
enum AgentStatus: String, Codable, Sendable {
    case idle
    case running
    case waitingForInput
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .waitingForInput: return "Waiting"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// A capability an agent advertises
struct AgentCapability: Hashable, Codable, Sendable {
    let name: String
    let description: String
}

/// A message sent between agents
struct AgentMessage: Sendable {
    let id: UUID
    let fromAgentId: String
    let toAgentId: String?
    let type: AgentMessageType
    let content: String
    let timestamp: Date
    let metadata: [String: String]

    init(from: String, to: String? = nil, type: AgentMessageType, content: String, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.fromAgentId = from
        self.toAgentId = to
        self.type = type
        self.content = content
        self.timestamp = Date()
        self.metadata = metadata
    }
}

/// Types of agent-to-agent messages
enum AgentMessageType: String, Sendable {
    case taskAssignment
    case taskResult
    case taskFailed
    case statusUpdate
    case requestReview
    case reviewResult
    case requestClarification
    case clarification
    case cancel
}

/// A sub-goal assigned to an agent
struct AgentTask: Identifiable, Sendable {
    let id: UUID
    let description: String
    let assignedAgentType: AgentType
    let dependencies: [UUID]
    let context: AgentTaskContext
    let maxRetries: Int
    let createdAt: Date

    init(id: UUID = UUID(), description: String, assignedAgentType: AgentType, dependencies: [UUID] = [], context: AgentTaskContext = AgentTaskContext(), maxRetries: Int = 2, createdAt: Date = Date()) {
        self.id = id
        self.description = description
        self.assignedAgentType = assignedAgentType
        self.dependencies = dependencies
        self.context = context
        self.maxRetries = maxRetries
        self.createdAt = createdAt
    }
}

/// Context information passed with a task
struct AgentTaskContext: Sendable {
    let conversationId: UUID?
    let relevantMessages: [String]
    let artifacts: [String: String]
    let additionalInstructions: String?
    let executionId: String?
    let sharedMemoryScope: String?
    let parentGoalId: String?

    init(
        conversationId: UUID? = nil,
        relevantMessages: [String] = [],
        artifacts: [String: String] = [:],
        additionalInstructions: String? = nil,
        executionId: String? = nil,
        sharedMemoryScope: String? = nil,
        parentGoalId: String? = nil
    ) {
        self.conversationId = conversationId
        self.relevantMessages = relevantMessages
        self.artifacts = artifacts
        self.additionalInstructions = additionalInstructions
        self.executionId = executionId
        self.sharedMemoryScope = sharedMemoryScope
        self.parentGoalId = parentGoalId
    }
}

/// Result from a completed agent task
struct AgentTaskResult: Sendable {
    let taskId: UUID
    let summary: String
    let output: String
    let artifacts: [String: String]
    let error: String?
}

/// Pre-defined agent team templates
struct AgentTeamTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let agents: [AgentType]

    static let all: [AgentTeamTemplate] = [
        AgentTeamTemplate(
            id: "software",
            name: "Software Project",
            description: "Plan, implement, and review code changes",
            agents: [.planner, .executor, .reviewer]
        ),
        AgentTeamTemplate(
            id: "research",
            name: "Research Paper",
            description: "Research a topic, organize findings, and produce a report",
            agents: [.planner, .researcher, .executor, .reviewer]
        ),
        AgentTeamTemplate(
            id: "analysis",
            name: "Data Analysis",
            description: "Analyze data, generate visualizations, and summarize insights",
            agents: [.planner, .executor, .reviewer]
        ),
        AgentTeamTemplate(
            id: "general",
            name: "General Assistant",
            description: "A balanced team for everyday tasks",
            agents: [.planner, .executor, .researcher]
        )
    ]
}
