import Foundation

final class GitStatusTool: Tool {
    var definition = ToolDefinition(
        id: "gitStatus",
        name: "Git Status",
        description: "Show working tree status (git status)",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Path to git repository (default: current directory)", type: .string, required: false)
        ])
    )

    private let executor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let path = (input["path"] ?? ".") as NSString
        let expanded = path.expandingTildeInPath
        let output = try await executor.run(executable: "/usr/bin/git", arguments: ["-C", expanded, "status", "--porcelain", "--branch"])
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        if lines.isEmpty {
            return "No changes (clean working tree)"
        }
        let staged = lines.filter { $0.hasPrefix("M ") || $0.hasPrefix("A ") || $0.hasPrefix("D ") || $0.hasPrefix("R ") || $0.hasPrefix("C ") }
        let unstaged = lines.filter { $0.hasPrefix(" M") || $0.hasPrefix(" D") || $0.hasPrefix("?") || $0.hasPrefix(" R") }
        var result = ""
        if let branchLine = lines.first(where: { $0.hasPrefix("##") }) {
            result += "\(branchLine.dropFirst(2).trimmingCharacters(in: .whitespaces))\n"
        }
        result += "\nStaged: \(staged.count)  Unstaged: \(unstaged.count)  Total: \(lines.filter { !$0.hasPrefix("##") }.count)\n\n"
        result += output
        return result
    }
}
