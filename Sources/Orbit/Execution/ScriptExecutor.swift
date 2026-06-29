import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "script-executor")

final class ScriptExecutor: CapabilityRuntime {
    var capabilityName: String { "shell" }
    private let timeoutSeconds: Double

    init(timeoutSeconds: Double = 30) {
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        log.debug("ScriptExecutor deinit — prefer ScriptShellTool for kernel-routed shell execution")
    }

    /// Run an executable with structured arguments (preferred — no shell injection).
    @discardableResult
    func run(executable: String, arguments: [String], context: ExecutionContext) async throws -> String {
        log.warning("ScriptExecutor.run called directly — bypasses kernel approval/audit. Register through ToolRegistry instead.")
        let process = Process()
        if executable.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }
        return try await withTaskCancellationHandler {
            try await launchAndWait(process)
        } onCancel: {
            process.terminate()
        }
    }

    /// Run a command string without shell interpreter injection risk.
    /// Parses the command into structured executable + arguments to avoid shell injection.
    /// Blocklisted patterns cause an immediate throw.
    @discardableResult
    func runShell(_ command: String, context: ExecutionContext) async throws -> String {
        let blocklistedPatterns = ["$(", "`", ";", "|"]
        for pattern in blocklistedPatterns {
            if command.contains(pattern) {
                throw OrbitError.securityBlocked("Command contains blocked shell metacharacter '\(pattern)'")
            }
        }
        let parts = command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let executable = parts.first, !executable.isEmpty else { return "" }
        let arguments = Array(parts.dropFirst())
        return try await run(executable: executable, arguments: arguments, context: context)
    }

    // MARK: - Legacy (remove after all call sites migrate)

    @available(*, deprecated, message: "Use runShell(_:context:) instead")
    @discardableResult
    func runShell(_ command: String) async throws -> String {
        let fallback = ExecutionContext.current ?? ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: nil, source: .internal, timeout: timeoutSeconds, createdAt: Date())
        return try await runShell(command, context: fallback)
    }

    @available(*, deprecated, message: "Use run(executable:arguments:context:) instead")
    @discardableResult
    func run(executable: String, arguments: [String]) async throws -> String {
        let fallback = ExecutionContext.current ?? ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: nil, source: .internal, timeout: timeoutSeconds, createdAt: Date())
        return try await run(executable: executable, arguments: arguments, context: fallback)
    }

    @available(*, deprecated, message: "Use runShell(_:context:) instead")
    @discardableResult
    func run(_ command: String) async throws -> String {
        let fallback = ExecutionContext.current ?? ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: nil, source: .internal, timeout: timeoutSeconds, createdAt: Date())
        return try await runShell(command, context: fallback)
    }

    // MARK: - Private

    private func launchAndWait(_ process: Process) async throws -> String {
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        return try await withUnsafeThrowingContinuation { continuation in
            let state = _ProcessState()

            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                state.lock.lock()
                guard !state.didFinish else { state.lock.unlock(); return }
                state.didFinish = true
                state.lock.unlock()

                process.terminate()
                _ = outputPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(throwing: OrbitError.timeout)
            }
            timer.resume()

            process.terminationHandler = { proc in
                timer.cancel()

                state.lock.lock()
                guard !state.didFinish else { state.lock.unlock(); return }
                state.didFinish = true
                state.lock.unlock()

                autoreleasepool {
                    let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if proc.terminationStatus == 0 {
                        let output = String(data: out, encoding: .utf8) ?? ""
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        continuation.resume(throwing: OrbitError.executionFailed("Exit code \(proc.terminationStatus)"))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                timer.cancel()
                continuation.resume(throwing: error)
            }
        }
    }

    private func readOutput(from pipe: Pipe, status: Int32) throws -> String {
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        guard status == 0 else {
            throw OrbitError.executionFailed("Exit code \(status)")
        }
        guard let output = String(data: out, encoding: .utf8) else {
            return ""
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Thread-safe mutable state for process termination coordination
private final class _ProcessState {
    var didFinish = false
    let lock = NSLock()
}
