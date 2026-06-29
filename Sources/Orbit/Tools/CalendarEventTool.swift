import Foundation

final class CalendarEventTool: Tool {
    var definition = ToolDefinition(
        id: "calendarEvent",
        name: "Create Calendar Event",
        description: "Create a new calendar event in the default calendar",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "title", description: "Event title", type: .string, required: true),
            ToolParameter(name: "date", description: "Date and time (e.g. 'tomorrow at 3pm' or '2024-12-25 10:00')", type: .string, required: true),
            ToolParameter(name: "duration", description: "Duration in minutes (default: 60)", type: .integer, required: false)
        ]),
        supportedPlatforms: ["macos"]
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let title = input["title"], !title.isEmpty else {
            return "No event title provided."
        }
        guard let dateStr = input["date"], !dateStr.isEmpty else {
            return "No event date provided."
        }
        let duration = input["duration"].flatMap { Int($0) } ?? 60

        let safeTitle = Self.appleScriptEscape(title)
        let safeDate = Self.appleScriptEscape(dateStr)
        let script = """
        tell application "Calendar"
            tell calendar 1
                make new event with properties {summary:"\(safeTitle)", start date:(date "\(safeDate)"), duration:\(duration)}
            end tell
        end tell
        """
        try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", script])
        return "Created event: \(title) on \(dateStr) for \(duration) minutes"
    }

    private static func appleScriptEscape(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\" & quote & \"")
    }
}
