import Foundation

final class TerminalRunTool: Tool {
    var definition = ToolDefinition(
        id: "terminalRun",
        name: "Run Terminal Command",
        description: "Execute a shell command and return its output. Use with caution.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "command", description: "Shell command to execute (e.g. 'echo hello' or 'ls -la ~')", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    var commandApprovalHandler: (@Sendable (String) async -> Bool)?

    private static let allowlist: Set<String> = [
        "ls", "pwd", "cat", "grep", "find", "echo", "head", "tail", "sort",
        "wc", "which", "date", "whoami", "uname", "printenv", "xargs", "cut",
        "tr", "comm", "diff", "file", "stat", "du", "df", "lsof",
        "ps", "tree", "env", "mkdir", "touch", "rmdir",
    ]

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let command = input["command"], !command.isEmpty else {
            return "No command provided."
        }
        if ToolRegistry.isBlocklisted(command) {
            return "Command blocked for security reasons."
        }

        let executable = parseExecutable(from: command)

        if Self.allowlist.contains(executable) {
            return try await scriptExecutor.runShell(command, context: ctx)
        }

        if let handler = commandApprovalHandler {
            guard await handler(executable) else {
                throw OrbitError.toolRequiresApproval("Command '\(executable)' was denied by the user")
            }
        } else {
            throw OrbitError.securityBlocked("Command '\(executable)' is not in the allowed list")
        }

        return try await scriptExecutor.runShell(command, context: ctx)
    }

    private func parseExecutable(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        return URL(fileURLWithPath: firstWord).lastPathComponent
    }
}
