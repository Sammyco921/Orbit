import Foundation

final class ReadFileTool: Tool {
    var definition = ToolDefinition(
        id: "readFile",
        name: "Read File",
        description: "Read the contents of a text file at the specified path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Full file path to read (e.g. ~/Desktop/note.txt)", type: .string, required: true)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        guard let path = input["path"], !path.isEmpty else {
            return "No path specified."
        }
        let expanded = (path as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).standardizingPath

        guard let sandboxed = Sandboxer.sandboxPath(resolved) else {
            throw OrbitError.securityBlocked("Access to '\(expanded)' is not allowed")
        }

        guard let content = try? String(contentsOfFile: sandboxed, encoding: .utf8) else {
            return "File not found or not readable: \(sandboxed)"
        }
        let lines = content.components(separatedBy: .newlines).prefix(200).joined(separator: "\n")
        return "Contents of \(sandboxed):\n\n\(lines)"
    }
}
