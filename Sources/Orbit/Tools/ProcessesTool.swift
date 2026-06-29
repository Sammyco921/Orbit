import Foundation

final class ProcessesTool: Tool {
    var definition = ToolDefinition(
        id: "processes",
        name: "List Processes",
        description: "List running processes sorted by CPU usage",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "limit", description: "Number of processes to show (default: 10)", type: .integer, required: false)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        let limit = input["limit"].flatMap { Int($0) } ?? 10
        let raw = try await scriptExecutor.run(executable: "/bin/ps", arguments: ["-eo", "pid,pcpu,pmem,comm", "-r"])
        let lines = raw.components(separatedBy: .newlines).prefix(limit).joined(separator: "\n")
        return lines
    }
}
