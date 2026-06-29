import Foundation

final class RememberTool: Tool {
    var definition = ToolDefinition(
        id: "remember",
        name: "Remember",
        description: "Store an important fact, preference, or piece of information in project memory for future reference across sessions",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "content", description: "The information to remember", type: .string, required: true),
            ToolParameter(name: "type", description: "Type of memory: fact, preference, note, decision", type: .string, required: false),
            ToolParameter(name: "workspaceId", description: "Optional workspace/project ID to scope the memory to", type: .string, required: false)
        ])
    )

    var memoryService: MemoryService?

    func run(input: [String: String]) async throws -> String {
        guard let content = input["content"], !content.isEmpty else {
            return "No content provided to remember."
        }
        guard let service = memoryService, let store = service.memoryStore else {
            return "Memory service not available."
        }
        let type = input["type"] ?? "fact"
        let workspaceId = input["workspaceId"]
        try store.storeGlobalItem(content: content, type: type, workspaceId: workspaceId)
        return "Stored in memory: \"\(content.prefix(100))\(content.count > 100 ? "..." : "")\""
    }
}

final class RecallTool: Tool {
    var definition = ToolDefinition(
        id: "recall",
        name: "Recall",
        description: "Search stored project memory for facts, preferences, notes, and past decisions",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "What to search for in memory", type: .string, required: false),
            ToolParameter(name: "type", description: "Filter by type: fact, preference, note, decision", type: .string, required: false),
            ToolParameter(name: "limit", description: "Maximum number of results (default 10)", type: .integer, required: false)
        ])
    )

    var memoryService: MemoryService?

    func run(input: [String: String]) async throws -> String {
        guard let service = memoryService, let store = service.memoryStore else {
            return "Memory service not available."
        }
        let limit = Int(input["limit"] ?? "") ?? 10
        let items = try store.searchGlobalItems(limit: limit)

        guard !items.isEmpty else {
            return "No memories found."
        }

        var result = "**Memories:**\n"
        for item in items {
            let date = Date(timeIntervalSince1970: item.createdAt)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            let dateStr = formatter.string(from: date)
            result += "- [\(item.type)] \(item.content) (\(dateStr))\n"
        }
        return result
    }
}
