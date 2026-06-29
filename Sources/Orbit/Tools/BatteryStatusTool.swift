import Foundation

final class BatteryStatusTool: Tool {
    var definition = ToolDefinition(
        id: "batteryStatus",
        name: "Battery Status",
        description: "Check the current battery status and power source",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        if Platform.current == .linux {
            return try await LinuxCommands.batteryStatus()
        }
        return try await scriptExecutor.run(executable: "/usr/bin/pmset", arguments: ["-g", "batt"])
    }
}
