import Foundation

final class GitCommitTool: Tool {
    var definition = ToolDefinition(
        id: "gitCommit",
        name: "Git Commit",
        description: "Stage all changes and commit with a message",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "message", description: "Commit message", type: .string, required: true)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        guard let message = input["message"], !message.isEmpty else {
            return "Commit message is required."
        }
        try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "add", "-A"])
        let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "commit", "-m", message])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
