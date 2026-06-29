import Foundation

final class DateTimeTool: Tool {
    var definition = ToolDefinition(
        id: "dateTime",
        name: "Date & Time",
        description: "Get the current date and time",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        try await scriptExecutor.run(executable: "/bin/date", arguments: ["+%A, %B %d, %Y at %I:%M %p %Z"])
    }
}
