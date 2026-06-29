import Foundation

final class ListDirectoryTool: Tool {
    var definition = ToolDefinition(
        id: "listDirectory",
        name: "List Directory",
        description: "List files and folders in a directory",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "path", description: "Directory path to list (default: current directory)", type: .string, required: false)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        let rawPath = input["path"] ?? "."
        let expanded = (rawPath as NSString).expandingTildeInPath
        let resolved = (expanded as NSString).standardizingPath

        guard let sandboxed = Sandboxer.sandboxPath(resolved) else {
            throw OrbitError.securityBlocked("Access to '\(expanded)' is not allowed")
        }

        let url = URL(fileURLWithPath: sandboxed)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: nil)
        else { return "Could not read: \(sandboxed)" }

        var entries: [String] = []
        for case let fileURL as URL in enumerator {
            if entries.count >= 20 { break }
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            entries.append(fileURL.lastPathComponent + (isDir ? "/" : ""))
        }
        return "Contents of \(sandboxed) (\(entries.count) items):\n" + entries.joined(separator: "\n")
    }
}
