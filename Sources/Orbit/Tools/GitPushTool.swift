import Foundation

final class GitPushTool: Tool {
    var definition = ToolDefinition(
        id: "gitPush",
        name: "Git Push",
        description: "Push commits to remote repository",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "remote", description: "Remote name (default: origin)", type: .string, required: false),
            ToolParameter(name: "branch", description: "Branch to push (default: current branch)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        let remote = input["remote"] ?? "origin"
        var args = ["-C", path, "push", remote]
        if let branch = input["branch"], !branch.isEmpty {
            args.append(branch)
        }
        let output = try await executor.run(executable: "/usr/bin/git", arguments: args)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

final class GitPullTool: Tool {
    var definition = ToolDefinition(
        id: "gitPull",
        name: "Git Pull",
        description: "Pull latest changes from remote repository",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "remote", description: "Remote name (default: origin)", type: .string, required: false),
            ToolParameter(name: "branch", description: "Branch to pull (default: current branch)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        let remote = input["remote"] ?? "origin"
        var args = ["-C", path, "pull", remote]
        if let branch = input["branch"], !branch.isEmpty {
            args.append(branch)
        }
        let output = try await executor.run(executable: "/usr/bin/git", arguments: args)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
