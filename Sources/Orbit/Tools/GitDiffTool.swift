import Foundation

final class GitDiffTool: Tool {
    var definition = ToolDefinition(
        id: "gitDiff",
        name: "Git Diff",
        description: "Show file diffs (git diff) — unstaged by default, or staged with --staged",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false),
            ToolParameter(name: "staged", description: "Show staged diff if true (default: false)", type: .string, required: false),
            ToolParameter(name: "file", description: "Specific file path to diff (optional)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = ((input["path"] ?? ".") as NSString).expandingTildeInPath
        var args = ["-C", path, "diff"]
        if input["staged"]?.lowercased() == "true" {
            args.append("--staged")
        }
        if let file = input["file"] {
            args.append("--")
            args.append(file)
        }
        let output = try await executor.run(executable: "/usr/bin/git", arguments: args)
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No differences found."
        }
        let lines = output.components(separatedBy: .newlines)
        if lines.count > 200 {
            return lines.prefix(200).joined(separator: "\n") + "\n\n... (truncated, \(lines.count - 200) more lines)"
        }
        return output
    }
}
