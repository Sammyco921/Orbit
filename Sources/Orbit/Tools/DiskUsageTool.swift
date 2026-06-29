import Foundation

final class DiskUsageTool: Tool {
    var definition = ToolDefinition(
        id: "diskUsage",
        name: "Disk Usage",
        description: "Check disk space usage on the root volume",
        inputSchema: ToolSchema(parameters: [])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        try await scriptExecutor.run(executable: "/bin/df", arguments: ["-h", "/"])
    }
}
