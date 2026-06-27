import Foundation
#if canImport(AppKit)
import AppKit
#endif

final class ClipboardTool: Tool {
    var definition = ToolDefinition(
        id: "clipboard",
        name: "Clipboard",
        description: "Read from or write to the system clipboard",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'read' to get clipboard contents, 'write' to set clipboard content", type: .string, required: true),
            ToolParameter(name: "content", description: "Text to write to clipboard (only used with action: write)", type: .string, required: false)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "read"

        if Platform.current == .linux {
            if action == "write" || action == "set" || action == "copy" {
                guard let content = input["content"], !content.isEmpty else {
                    return "Nothing to copy. Provide content parameter."
                }
                try await LinuxCommands.clipboardCopy(content)
                return "Copied to clipboard"
            }
            let content = try await LinuxCommands.clipboardPaste()
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return "Clipboard is empty"
            }
            return "Clipboard: \(trimmed.prefix(2000))"
        }

        if action == "write" || action == "set" || action == "copy" {
            guard let content = input["content"], !content.isEmpty else {
                return "Nothing to copy. Provide content parameter."
            }
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(content, forType: .string)
            }
            return "Copied to clipboard"
        }

        let pasteboard = NSPasteboard.general
        guard let content = pasteboard.string(forType: .string) else {
            return "Clipboard is empty or contains non-text data."
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Clipboard is empty"
        }
        return "Clipboard: \(trimmed.prefix(2000))"
    }
}
