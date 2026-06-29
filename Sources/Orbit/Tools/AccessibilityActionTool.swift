import Foundation

final class AccessibilityActionTool: Tool {
    var definition = ToolDefinition(
        id: "accessibilityAction",
        name: "Accessibility Actions",
        description: "Perform accessibility actions: get UI element info, press buttons, toggle checkboxes, etc.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "action", description: "'describe' to describe UI of frontmost app, 'press' to press a button by name, 'click' to click a UI element by description", type: .string, required: true),
            ToolParameter(name: "target", description: "Description of the UI element to interact with", type: .string, required: false)
        ]),
        supportedPlatforms: ["macos"]
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let action = input["action"]?.lowercased() ?? "describe"

        switch action {
        case "describe":
            let raw = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                set appName to name of frontApp
                set uiElements to every UI element of frontApp
                set output to "Frontmost App: " & appName & linefeed
                repeat with elem in uiElements
                    try
                        set output to output & role of elem & ": " & (description of elem) & linefeed
                    end try
                end repeat
                return output
            end tell
            """])
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)

        case "press":
            guard let target = input["target"], !target.isEmpty else {
                return "No target provided."
            }
            let escaped = target.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let raw = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
            tell application "System Events"
                tell (first application process whose frontmost is true)
                    set uiElems to every UI element
                    repeat with elem in uiElems
                        try
                            if description of elem contains "\(escaped)" then
                                perform action "AXPress" of elem
                                return "Pressed: " & description of elem
                            end if
                        end try
                    end repeat
                    return "Element not found: " & "\(escaped)"
                end tell
            end tell
            """])
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)

        default:
            return "Unknown action: \(action). Use 'describe' or 'press'."
        }
    }
}
