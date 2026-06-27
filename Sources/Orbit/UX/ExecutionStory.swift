import Foundation

// MARK: - Story Step Status

enum StoryStepStatus: String, Sendable, Codable {
    case pending
    case inProgress
    case completed
    case failed
    case timedOut
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .timedOut, .cancelled: true
        case .pending, .inProgress: false
        }
    }

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .failed: "Failed"
        case .timedOut: "Timed Out"
        case .cancelled: "Cancelled"
        }
    }
}

// MARK: - Story Step (unified step model)

struct StoryStep: Identifiable, Sendable, Codable {
    let id: UUID
    let order: Int
    let description: String
    let actionSummary: String?
    let expectedOutput: String?
    let toolID: String?
    var status: StoryStepStatus
    var streamedTokens: String?
    var output: String?
    var detail: String?
    var timestamp: Date
    var toolInput: String?
    var permissionMode: String?
    var kernelDecision: String?
    var traceID: String?

    init(
        id: UUID = UUID(),
        order: Int,
        description: String,
        actionSummary: String? = nil,
        expectedOutput: String? = nil,
        toolID: String? = nil,
        status: StoryStepStatus = .pending,
        streamedTokens: String? = nil,
        output: String? = nil,
        detail: String? = nil,
        timestamp: Date = Date(),
        toolInput: String? = nil,
        permissionMode: String? = nil,
        kernelDecision: String? = nil,
        traceID: String? = nil
    ) {
        self.id = id
        self.order = order
        self.description = description
        self.actionSummary = actionSummary
        self.expectedOutput = expectedOutput
        self.toolID = toolID
        self.status = status
        self.streamedTokens = streamedTokens
        self.output = output
        self.detail = detail
        self.timestamp = timestamp
        self.toolInput = toolInput
        self.permissionMode = permissionMode
        self.kernelDecision = kernelDecision
        self.traceID = traceID
    }
}

// MARK: - Execution Story (unified canonical model)

struct ExecutionStory: Identifiable, Sendable, Codable {
    let id: UUID
    let intent: String
    var steps: [StoryStep]
    var summary: SummarySection?
    let createdAt: Date
    var executionStartedAt: Date?
    var executionEndedAt: Date?

    init(
        id: UUID = UUID(),
        intent: String,
        steps: [StoryStep] = [],
        summary: SummarySection? = nil,
        createdAt: Date = Date(),
        executionStartedAt: Date? = nil,
        executionEndedAt: Date? = nil
    ) {
        self.id = id
        self.intent = intent
        self.steps = steps
        self.summary = summary
        self.createdAt = createdAt
        self.executionStartedAt = executionStartedAt
        self.executionEndedAt = executionEndedAt
    }
}

// MARK: - Story computed state

extension ExecutionStory {
    var hasPartialFailure: Bool {
        steps.contains { $0.status == .failed || $0.status == .timedOut }
    }

    var cancelledAtIndex: Int? {
        steps.firstIndex { $0.status == .cancelled }
    }
}

// MARK: - Result Section

struct ResultSection: Sendable {
    let content: String
}

// MARK: - Summary Section (shared)

struct SummarySection: Codable, Sendable {
    let whatWasDone: String
    let whyItWasDone: String
    let resultSummary: String
}

// MARK: - Execution Errors

enum ExecutionError: Error, LocalizedError {
    case toolTimedOut(String)
    case llmTimedOut
    case streamInterrupted
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolTimedOut(let tool): "Tool timed out: \(tool)"
        case .llmTimedOut: "LLM response timed out"
        case .streamInterrupted: "Response stream interrupted"
        case .stepFailed(let reason): reason
        }
    }
}
