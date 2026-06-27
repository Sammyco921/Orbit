import Foundation

struct ExecutionContext: Sendable {
    let executionId: String
    let conversationId: String?
    let workspaceId: String?
    let source: ExecutionSource
    let timeout: TimeInterval?
    let createdAt: Date
}

extension ExecutionContext {
    @TaskLocal static var current: ExecutionContext?
}
