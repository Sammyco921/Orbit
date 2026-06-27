import Foundation

// MARK: - Execution Events

struct WorkflowStartedEvent: Event {
    let executionId: String
    let workflowId: String
    let workflowName: String
    let triggerType: String
    let timestamp: Date
}

struct WorkflowStepCompletedEvent: Event {
    let executionId: String
    let stepName: String
    let stepIndex: Int
    let durationMs: Double
    let outcome: String
    let error: String?
    let timestamp: Date
}

struct WorkflowCompletedEvent: Event {
    let executionId: String
    let workflowId: String
    let status: String
    let totalSteps: Int
    let failedSteps: Int
    let totalDurationMs: Double
    let error: String?
    let timestamp: Date
}

struct GoalStartedEvent: Event {
    let goalId: String
    let description: String
    let timestamp: Date
}

struct GoalCompletedEvent: Event {
    let goalId: String
    let outcome: String
    let durationMs: Double
    let timestamp: Date
}

struct AgentActionEvent: Event {
    let executionId: String
    let actionType: String
    let toolName: String?
    let detail: String?
    let timestamp: Date
}
