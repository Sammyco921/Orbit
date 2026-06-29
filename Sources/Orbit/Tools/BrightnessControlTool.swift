import Foundation

final class BrightnessControlTool: Tool {
    var definition = ToolDefinition(
        id: "brightnessControl",
        name: "Brightness Control",
        description: "Get or set display brightness level",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'get' to read brightness, 'set' to set brightness (use level param)", type: .string, required: true),
            ToolParameter(name: "level", description: "Brightness level 0-100 (only for action: set)", type: .integer, required: false)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "get"

        if Platform.current == .linux {
            switch action {
            case "set":
                guard let levelStr = input["level"], let level = Int(levelStr), (0...100).contains(level) else {
                    return "Provide a level between 0 and 100."
                }
                try await LinuxCommands.setBrightness(level)
                return "Brightness set to \(level)%"
            default:
                let brightness = try await LinuxCommands.getBrightness()
                return "\(brightness)%"
            }
        }

        switch action {
        case "set":
            guard let levelStr = input["level"], let level = Int(levelStr), (0...100).contains(level) else {
                return "Provide a level between 0 and 100."
            }
            try await scriptExecutor.runShell("brightness \(Double(level) / 100.0)")
            return "Brightness set to \(level)%"

        default:
            let raw = try await scriptExecutor.runShell("brightness -l")
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
