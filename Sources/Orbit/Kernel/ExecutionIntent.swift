import Foundation

struct ExecutionIntent {
    let action: ExecutionAction
    let input: [String: String]
    let sessionId: String?
    let conversationId: String?
    let source: ExecutionSource
    let approvalMode: ApprovalMode
}

enum ExecutionAction {
    case tool(String)
}

enum ExecutionSource: String, Sendable {
    case agent
    case user
    case event
    case `internal`
}

struct ExecutionResult {
    let output: String
    let success: Bool
    let durationMs: Double
}
