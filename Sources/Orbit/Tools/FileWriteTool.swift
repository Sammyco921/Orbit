import Foundation

final class FileWriteTool: Tool {
    var definition = ToolDefinition(
        id: "writeFile",
        name: "Write File",
        description: "Write text content to a file at the specified path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Full file path to write to (e.g. ~/Desktop/note.txt)", type: .string, required: true),
            ToolParameter(name: "content", description: "Text content to write to the file", type: .string, required: true)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        guard let path = input["path"], !path.isEmpty else {
            return "No path specified."
        }
        guard let content = input["content"], !content.isEmpty else {
            return "No content specified."
        }

        let expanded = (path as NSString).expandingTildeInPath
        let fileURL = URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let desktopDir = homeDir.appendingPathComponent("Desktop")
        let docsDir = homeDir.appendingPathComponent("Documents")
        let projectDir = homeDir.appendingPathComponent("Desktop/Orbit/Artifacts")
        guard fileURL.absoluteString.hasPrefix(homeDir.absoluteString) ||
              fileURL.absoluteString.hasPrefix(desktopDir.absoluteString) ||
              fileURL.absoluteString.hasPrefix(docsDir.absoluteString) ||
              fileURL.absoluteString.hasPrefix(projectDir.absoluteString) else {
            throw OrbitError.securityBlocked("Path '\(expanded)' is outside allowed directories")
        }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return "Written to \(fileURL.path)"
    }
}
