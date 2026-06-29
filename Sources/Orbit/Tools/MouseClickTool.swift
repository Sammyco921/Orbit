import Foundation

final class MouseClickTool: Tool {
    var definition = ToolDefinition(
        id: "mouseClick",
        name: "Mouse Click",
        description: "Simulate a mouse click at the current cursor position or at specified coordinates",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "button", description: "Mouse button: 'left', 'right', or 'center' (default: left)", type: .string, required: false),
            ToolParameter(name: "x", description: "X coordinate (optional, uses current position if omitted)", type: .integer, required: false),
            ToolParameter(name: "y", description: "Y coordinate (optional, uses current position if omitted)", type: .integer, required: false)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let button = input["button"]?.lowercased() ?? "left"

        if let xStr = input["x"], let yStr = input["y"], let x = Int(xStr), let y = Int(yStr) {
            if Platform.current == .linux {
                try await LinuxCommands.mouseClickAt(x: x, y: y, button: button)
            } else {
                try await macClickAt(x: x, y: y, button: button)
            }
            return "Clicked \(button) at (\(x), \(y))"
        } else {
            if Platform.current == .linux {
                try await LinuxCommands.mouseClick(button: button)
            } else {
                try await macClick(button: button)
            }
            return "Clicked \(button) at current position"
        }
    }

    private func macClick(button: String) async throws {
        let osaButton: String
        switch button {
        case "right": osaButton = "button 2"
        case "center": osaButton = "button 3"
        default: osaButton = "button 1"
        }
        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            click \(osaButton)
        end tell
        """])
    }

    private func macClickAt(x: Int, y: Int, button: String) async throws {
        let osaButton: String
        switch button {
        case "right": osaButton = "button 2"
        case "center": osaButton = "button 3"
        default: osaButton = "button 1"
        }
        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            set currentPos to position of mouse
            set position of mouse to {\(x), \(y)}
            delay 0.1
            click \(osaButton)
            set position of mouse to currentPos
        end tell
        """])
    }
}
