import Foundation

final class CreateFolderTool: Tool {
    var definition = ToolDefinition(
        id: "createFolder",
        name: "Create Folder",
        description: "Create a new folder/directory at the specified path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Full path for the new folder (e.g. ~/Desktop/NewFolder)", type: .string, required: true)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        guard let path = input["path"], !path.isEmpty else {
            return "No path specified."
        }
        let expanded = (path as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: expanded), withIntermediateDirectories: true)
        return "Created \(expanded)"
    }
}
