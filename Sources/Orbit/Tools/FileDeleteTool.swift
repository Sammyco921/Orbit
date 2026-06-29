import Foundation

final class FileDeleteTool: Tool {
    var definition = ToolDefinition(
        id: "fileDelete",
        name: "Delete File",
        description: "Permanently delete a file or folder at the specified path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Full path to the file or folder to delete", type: .string, required: true)
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
        guard FileManager.default.fileExists(atPath: sandboxed) else {
            return "File not found: \(sandboxed)"
        }
        try FileManager.default.removeItem(at: URL(fileURLWithPath: sandboxed))
        return "Deleted \(sandboxed)"
    }
}
