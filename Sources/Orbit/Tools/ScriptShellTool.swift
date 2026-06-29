import Foundation

final class ScriptShellTool: Tool {
    var definition = ToolDefinition(
        id: "scriptShell",
        name: "Shell Script Executor",
        description: "Execute a shell command or script with structured arguments. Routes through kernel for approval, auditing, and cancellation.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "executable", description: "Path or name of the executable to run", type: .string, required: true),
            ToolParameter(name: "arguments", description: "JSON array of argument strings (e.g. [\"-la\", \"/tmp\"])", type: .string, required: false),
            ToolParameter(name: "command", description: "Raw shell command string (alternative to executable+arguments)", type: .string, required: false),
        ]),
        requiredPermission: .requiresApproval
    )

    private let executor: ScriptExecutor

    init(timeoutSeconds: Double = 30) {
        self.executor = ScriptExecutor(timeoutSeconds: timeoutSeconds)
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }

        if let command = input["command"], !command.isEmpty {
            return try await executor.runShell(command, context: ctx)
        }

        guard let executable = input["executable"], !executable.isEmpty else {
            return "Either 'command' or 'executable' must be provided."
        }

        let arguments: [String]
        if let argsJSON = input["arguments"], !argsJSON.isEmpty {
            guard let data = argsJSON.data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: data) else {
                return "Invalid 'arguments' JSON array."
            }
            arguments = parsed
        } else {
            arguments = []
        }

        return try await executor.run(executable: executable, arguments: arguments, context: ctx)
    }
}
