import Foundation

final class FrontmostAppTool: Tool {
    var definition = ToolDefinition(
        id: "frontmostApp",
        name: "Active Application",
        description: "Get the name of the currently active (frontmost) application",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        if Platform.current == .linux {
            return try await LinuxCommands.frontmostApp()
        }
        return try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", "tell application \"System Events\" to get name of first application process whose frontmost is true"])
    }
}
