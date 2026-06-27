import Foundation

final class FinderSearchTool: Tool {
    var definition = ToolDefinition(
        id: "finderSearch",
        name: "Find Files",
        description: "Search for files using Spotlight (mdfind)",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Filename or search term to look for", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let query = input["query"], !query.isEmpty else {
            return "Search for what?"
        }
        guard !query.hasPrefix("-") else {
            throw OrbitError.securityBlocked("Invalid query: cannot start with '-'")
        }
        if Platform.current == .linux {
            return try await LinuxCommands.fileSearch(query: query)
        }
        return try await scriptExecutor.run(executable: "/usr/bin/mdfind", arguments: ["-name", query])
    }
}
