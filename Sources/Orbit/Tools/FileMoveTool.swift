import Foundation

final class FileMoveTool: Tool {
    var definition = ToolDefinition(
        id: "fileMove",
        name: "Move or Copy File",
        description: "Move or copy a file from source to destination path",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "source", description: "Source file path", type: .string, required: true),
            ToolParameter(name: "destination", description: "Destination file path", type: .string, required: true),
            ToolParameter(name: "action", description: "'move' or 'copy' (default: move)", type: .string, required: false)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        guard let source = input["source"], !source.isEmpty else {
            return "No source path specified."
        }
        guard let destination = input["destination"], !destination.isEmpty else {
            return "No destination path specified."
        }

        let srcExpanded = (source as NSString).expandingTildeInPath
        let dstExpanded = (destination as NSString).expandingTildeInPath
        let srcResolved = (srcExpanded as NSString).standardizingPath
        let dstResolved = (dstExpanded as NSString).standardizingPath

        guard let sandboxedSrc = Sandboxer.sandboxPath(srcResolved) else {
            throw OrbitError.securityBlocked("Access to source '\(srcExpanded)' is not allowed")
        }
        guard let sandboxedDst = Sandboxer.sandboxPath(dstResolved) else {
            throw OrbitError.securityBlocked("Access to destination '\(dstExpanded)' is not allowed")
        }

        let srcURL = URL(fileURLWithPath: sandboxedSrc)
        let dstURL = URL(fileURLWithPath: sandboxedDst)

        guard FileManager.default.fileExists(atPath: sandboxedSrc) else {
            return "Source not found: \(sandboxedSrc)"
        }

        let action = input["action"]?.lowercased() ?? "move"

        if action == "copy" {
            try FileManager.default.copyItem(at: srcURL, to: dstURL)
            return "Copied \(sandboxedSrc) to \(sandboxedDst)"
        } else {
            try FileManager.default.moveItem(at: srcURL, to: dstURL)
            return "Moved \(sandboxedSrc) to \(sandboxedDst)"
        }
    }
}
