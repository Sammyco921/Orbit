import Foundation

final class GitLogTool: Tool {
    var definition = ToolDefinition(
        id: "gitLog",
        name: "Git Log",
        description: "Show commit history (git log) with optional path filter",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "count", description: "Number of commits to show (default: 10)", type: .string, required: false),
            ToolParameter(name: "file", description: "Show history for a specific file path (optional)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        let count = input["count"] ?? "10"
        var args = ["-C", path, "log", "--oneline", "--decorate", "-\(count)"]
        if let file = input["file"] {
            args.append("--")
            args.append(file)
        }
        let output = try await executor.run(executable: "/usr/bin/git", arguments: args)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No commits found."
        }
        return output
    }
}
