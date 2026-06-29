import Foundation

final class SpeakTool: Tool {
    var definition = ToolDefinition(
        id: "speak",
        name: "Text to Speech",
        description: "Speak text aloud using the system speech synthesizer",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "Text to speak aloud", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"], !text.isEmpty else {
            return "What should I say?"
        }
        if Platform.current == .linux {
            try await LinuxCommands.speak(text)
            return "Speaking: \(text)"
        }
        try await scriptExecutor.run(executable: "/usr/bin/say", arguments: [text])
        return "Speaking: \(text)"
    }
}
