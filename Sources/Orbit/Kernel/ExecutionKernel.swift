import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "kernel")

final class ExecutionKernel {
    private let toolRegistry: ToolRegistry
    private let permissionGate: PermissionGate
    private let eventCommitter: EventCommitter

    init(
        toolRegistry: ToolRegistry,
        permissionGate: PermissionGate,
        eventCommitter: EventCommitter
    ) {
        self.toolRegistry = toolRegistry
        self.permissionGate = permissionGate
        self.eventCommitter = eventCommitter
    }

    func execute(intent: ExecutionIntent) async throws -> ExecutionResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard case .tool(let name) = intent.action else {
            throw KernelError.unsupportedAction
        }

        guard let tool = toolRegistry.tool(named: name) else {
            throw OrbitError.toolNotFound(name)
        }

        let sid = intent.sessionId ?? "tool-\(UUID().uuidString.prefix(8))"

        let context = ExecutionContext(
            executionId: sid,
            conversationId: intent.conversationId,
            workspaceId: nil,
            source: intent.source,
            timeout: nil,
            createdAt: Date()
        )

        do {
            try await permissionGate.check(intent: intent, tool: tool)
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            eventCommitter.commitDenied(
                intent: intent,
                toolName: name,
                sessionId: sid,
                durationMs: elapsed
            )
            throw error
        }

        try Task.checkCancellation()

        let output: String
        do {
            output = try await ExecutionContext.$current.withValue(context) {
                try await tool.run(input: intent.input)
            }
        } catch is CancellationError {
            PendingApproval.shared.cancelPending(for: name)
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            eventCommitter.commitFailure(
                intent: intent,
                toolName: name,
                error: CancellationError(),
                sessionId: sid,
                durationMs: elapsed
            )
            throw CancellationError()
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            eventCommitter.commitFailure(
                intent: intent,
                toolName: name,
                error: error,
                sessionId: sid,
                durationMs: elapsed
            )
            throw error
        }

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        eventCommitter.commitSuccess(
            intent: intent,
            toolName: name,
            output: output,
            sessionId: sid,
            durationMs: elapsed
        )

        return ExecutionResult(output: output, success: true, durationMs: elapsed)
    }
}

enum KernelError: Error, LocalizedError, Equatable {
    case unsupportedAction
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unsupportedAction:
            return "The requested action is not supported by the execution kernel."
        case .notConfigured:
            return "Execution kernel is not configured."
        }
    }
}
