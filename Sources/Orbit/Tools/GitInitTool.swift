import Foundation

final class GitInitTool: Tool {
    var definition = ToolDefinition(
        id: "gitInit",
        name: "Git Init",
        description: "Initialize a new git repository at the specified path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Directory path to initialize as a git repository", type: .string, required: true)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let rawPath = input["path"], !rawPath.isEmpty else {
            return "Path is required."
        }
        let expanded = (rawPath as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: expanded, withIntermediateDirectories: true)
        let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", expanded, "init"])
        return "Initialized empty git repository at \(expanded)"
    }
}

final class GitCloneTool: Tool {
    var definition = ToolDefinition(
        id: "gitClone",
        name: "Git Clone",
        description: "Clone a remote repository into a local directory",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "url", description: "Remote repository URL", type: .string, required: true),
            ToolParameter(name: "path", description: "Destination directory (default: current directory / repo name)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let url = input["url"], !url.isEmpty else {
            return "Repository URL is required."
        }
        var args = ["clone", url]
        if let dest = input["path"], !dest.isEmpty {
            args.append((dest as NSString).expandingTildeInPath)
        }
        let output = try await executor.run(executable: "/usr/bin/git", arguments: args)
        let repoName = url.split(separator: "/").last?.split(separator: ".").first ?? "repository"
        return "Cloned \(url) into \(input["path"] ?? String(repoName))"
    }
}
