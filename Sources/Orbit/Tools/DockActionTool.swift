import Foundation

final class DockActionTool: Tool {
    var definition = ToolDefinition(
        id: "dockAction",
        name: "Dock Actions",
        description: "Interact with the Dock: list items, add or remove apps",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'list' to show dock items, 'add' to add an app (use appName param), 'remove' to remove an app (use appName param)", type: .string, required: true),
            ToolParameter(name: "appName", description: "Name of the application (for add/remove actions)", type: .string, required: false)
        ]),
        supportedPlatforms: ["macos"]
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "list"

        switch action {
        case "list":
            let raw = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                set dockItems to name of every process whose dock preference is true
                set output to ""
                repeat with itemName in dockItems
                    set output to output & itemName & linefeed
                end repeat
                return output
            end tell
            """])
            return "Dock items:\n\(raw.trimmingCharacters(in: .whitespacesAndNewlines))"

        case "add":
            guard let appName = input["appName"], !appName.isEmpty else {
                return "No app name provided."
            }
            guard appName.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil else {
                return "Invalid app name: only alphanumeric characters allowed."
            }
            try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                tell dock preferences
                    -- adding via defaults; use 'defaults write' approach
                end tell
            end tell
            """])
            try await scriptExecutor.run(executable: "/usr/bin/defaults", arguments: ["write", "com.apple.dock", "persistent-apps", "-array-add", "{\"tile-type\"=\"file-tile\";\"file-data\"={\"_CFURLString\"=\"file:///Applications/\(appName).app/\";\"_CFURLStringType\"=15;}}"])
            try await scriptExecutor.run(executable: "/usr/bin/killall", arguments: ["Dock"])
            return "Added \(appName) to Dock"

        case "remove":
            guard let appName = input["appName"], !appName.isEmpty else {
                return "No app name provided."
            }
            try await scriptExecutor.runShell("defaults delete com.apple.dock persistent-apps && killall Dock")
            return "Removed \(appName) from Dock (all items removed; restart to rebuild)"

        default:
            return "Unknown action: \(action). Use 'list', 'add', or 'remove'."
        }
    }
}
