import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "events")

final class EventCommitter {
    private let auditService: AuditService?
    private let eventBus: EventBus

    init(auditService: AuditService?, eventBus: EventBus) {
        self.auditService = auditService
        self.eventBus = eventBus
    }

    private func record(_ entry: ExecutionLogEntry) {
        guard let auditService else {
            log.warning("No auditService configured — execution record dropped for tool '\(entry.toolName)'")
            return
        }
        auditService.record(entry)
    }

    func commitSuccess(
        intent: ExecutionIntent,
        toolName: String,
        output: String,
        sessionId: String,
        durationMs: Double
    ) {
        let entry = ExecutionLogEntry(
            sessionId: sessionId,
            toolName: toolName,
            inputJSON: intent.input.isEmpty ? nil : encodeJSON(intent.input),
            outputJSON: output.isEmpty ? nil : String(output.prefix(10000)),
            outcome: "succeeded",
            conversationId: intent.conversationId,
            durationMs: durationMs
        )
        record(entry)
        eventBus.publish(ToolExecutedEvent(toolName: toolName, result: output))
    }

    func commitFailure(
        intent: ExecutionIntent,
        toolName: String,
        error: Error,
        sessionId: String,
        durationMs: Double
    ) {
        let entry = ExecutionLogEntry(
            sessionId: sessionId,
            toolName: toolName,
            inputJSON: intent.input.isEmpty ? nil : encodeJSON(intent.input),
            outcome: "failed",
            errorDetail: error.localizedDescription,
            conversationId: intent.conversationId,
            durationMs: durationMs
        )
        record(entry)
        eventBus.publish(ToolExecutedEvent(toolName: toolName, result: "failed: \(error.localizedDescription)"))
    }

    func commitDenied(
        intent: ExecutionIntent,
        toolName: String,
        sessionId: String,
        durationMs: Double
    ) {
        let entry = ExecutionLogEntry(
            sessionId: sessionId,
            toolName: toolName,
            inputJSON: intent.input.isEmpty ? nil : encodeJSON(intent.input),
            outcome: "denied",
            conversationId: intent.conversationId,
            durationMs: durationMs
        )
        record(entry)
    }

    private func encodeJSON(_ dict: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(dict),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}
