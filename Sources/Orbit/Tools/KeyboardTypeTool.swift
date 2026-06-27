import Foundation

final class KeyboardTypeTool: Tool {
    var definition = ToolDefinition(
        id: "keyboardType",
        name: "Type Text",
        description: "Simulate keyboard typing of specified text into the active application",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "Text to type", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"], !text.isEmpty else {
            return "No text provided to type."
        }
        if Platform.current == .linux {
            try await LinuxCommands.keyboardType(text: text)
        } else {
            let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                keystroke "\(escaped)"
            end tell
            """])
        }
        return "Typed: \(text.prefix(100))"
    }
}
