import Foundation

final class VolumeControlTool: Tool {
    var definition = ToolDefinition(
        id: "volumeControl",
        name: "Volume Control",
        description: "Get or set system volume, mute or unmute audio",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'get' to read volume, 'set' to set volume (use level param), 'mute', 'unmute'", type: .string, required: true),
            ToolParameter(name: "level", description: "Volume level 0-100 (only for action: set)", type: .integer, required: false)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "get"

        if Platform.current == .linux {
            switch action {
            case "mute":
                try await LinuxCommands.setVolume(0)
                return "Muted"
            case "unmute":
                try await LinuxCommands.setVolume(50)
                return "Unmuted"
            case "set":
                guard let levelStr = input["level"], let level = Int(levelStr), (0...100).contains(level) else {
                    return "Provide a level between 0 and 100."
                }
                try await LinuxCommands.setVolume(level)
                return "Volume set to \(level)%"
            default:
                let vol = try await LinuxCommands.getVolume()
                return "Current volume: \(vol)%"
            }
        }

        switch action {
        case "mute":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "set volume with output muted"])
            return "Muted"

        case "unmute":
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "set volume without output muted"])
            return "Unmuted"

        case "set":
            guard let levelStr = input["level"], let level = Int(levelStr), (0...100).contains(level) else {
                return "Provide a level between 0 and 100."
            }
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "set volume output volume \(level)"])
            return "Volume set to \(level)%"

        default:
            let raw = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "output volume of (get volume settings)"])
            return "Current volume: \(raw.trimmingCharacters(in: .whitespacesAndNewlines))%"
        }
    }
}
