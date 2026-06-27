import Foundation

struct ExecutionLogEntry: Identifiable, Codable, Sendable {
    let id: String
    let sessionId: String
    let toolName: String
    let inputJSON: String?
    let outputJSON: String?
    let outcome: String
    let errorDetail: String?
    let approvalId: String?
    let conversationId: String?
    let durationMs: Double
    let createdAt: Date
    let userContext: String?

    init(
        id: String = UUID().uuidString,
        sessionId: String,
        toolName: String,
        inputJSON: String? = nil,
        outputJSON: String? = nil,
        outcome: String,
        errorDetail: String? = nil,
        approvalId: String? = nil,
        conversationId: String? = nil,
        durationMs: Double = 0,
        userContext: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.toolName = toolName
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.outcome = outcome
        self.errorDetail = errorDetail
        self.approvalId = approvalId
        self.conversationId = conversationId
        self.durationMs = durationMs
        self.createdAt = Date()
        self.userContext = userContext
    }
}
