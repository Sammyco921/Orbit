import Foundation

final class GitBranchTool: Tool {
    var definition = ToolDefinition(
        id: "gitBranch",
        name: "Git Branch",
        description: "List, create, switch, or delete branches. Use action: 'list', 'create', 'switch', 'delete'",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "action", description: "Operation: 'list', 'create', 'switch', 'delete' (default: 'list')", type: .string, required: false),
            ToolParameter(name: "branch", description: "Branch name (required for create/switch/delete)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        let action = input["action"] ?? "list"
        let branch = input["branch"] ?? ""

        switch action {
        case "list":
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "branch"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)

        case "create":
            guard !branch.isEmpty else { return "Branch name is required for create." }
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "branch", branch])
            return "Created branch '\(branch)'."

        case "switch":
            guard !branch.isEmpty else { return "Branch name is required for switch." }
            guard !branch.hasPrefix("-") else { return "Branch name cannot start with '-'." }
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "checkout", branch])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)

        case "delete":
            guard !branch.isEmpty else { return "Branch name is required for delete." }
            guard !branch.hasPrefix("-") else { return "Branch name cannot start with '-'." }
            let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", path, "branch", "-d", branch])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            return "Unknown action '\(action)'. Use: list, create, switch, delete"
        }
    }
}
