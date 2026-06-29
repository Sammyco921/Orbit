import Foundation

final class GitStashTool: Tool {
    var definition = ToolDefinition(
        id: "gitStash",
        name: "Git Stash",
        description: "Stash changes, list stashes, or pop a stash. Use action: 'push', 'list', 'pop'",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "action", description: "Operation: 'push', 'list', 'pop' (default: 'push')", type: .string, required: false),
            ToolParameter(name: "message", description: "Stash description (optional, for push)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        let action = input["action"] ?? "push"

        switch action {
        case "list":
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "stash", "list"])
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "No stashes found." : trimmed

        case "pop":
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "stash", "pop"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)

        case "push":
            var args = ["-C", path, "stash", "push"]
            if let msg = input["message"], !msg.isEmpty {
                args.append("-m")
                args.append(msg)
            }
            let result = try await executor.run(executable: "/usr/bin/git", arguments: args)
            let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Working directory stashed." : trimmed

        default:
            return "Unknown action '\(action)'. Use: push, list, pop"
        }
    }
}
