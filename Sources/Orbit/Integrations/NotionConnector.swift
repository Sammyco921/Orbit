import Foundation

final class NotionConnector: APIConnector, Connector {
    let id = "notion"
    let name = "Notion"
    let requiredScopes: [String] = []
    var tools: [Tool] {
        [CreateNotionPageTool(connector: self), QueryNotionDatabaseTool(connector: self)]
    }

    var baseURL: String { "https://api.notion.com/v1" }

    override func authenticatedRequest(method: String, url: String, body: Data? = nil, headers: [String: String] = [:], workspaceId: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var extraHeaders = headers
        extraHeaders["Notion-Version"] = "2022-06-28"
        return try await super.authenticatedRequest(method: method, url: url, body: body, headers: extraHeaders, workspaceId: workspaceId)
    }
}

// MARK: - Create Page Tool

final class CreateNotionPageTool: Tool {
    var definition = ToolDefinition(
        id: "createNotionPage",
        name: "Create Notion Page",
        description: "Create a new page in a Notion database or as a child of another page.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "parentId", description: "Parent page or database ID", type: .string, required: true),
            ToolParameter(name: "title", description: "Page title", type: .string, required: true),
            ToolParameter(name: "content", description: "Page content as plain text (converted to Notion blocks)", type: .string, required: false)
        ])
    )

    private let connector: NotionConnector

    init(connector: NotionConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let parentId = input["parentId"], !parentId.isEmpty else { return "No parent ID specified." }
        guard let title = input["title"], !title.isEmpty else { return "No title specified." }

        var body: [String: Any] = [
            "parent": ["page_id": parentId],
            "properties": [
                "title": [
                    "title": [
                        ["text": ["content": title]]
                    ]
                ]
            ]
        ]

        if let content = input["content"], !content.isEmpty {
            body["children"] = [
                ["object": "block", "type": "paragraph", "paragraph": ["rich_text": [["type": "text", "text": ["content": content]]]]]
            ]
        }

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "\(connector.baseURL)/pages",
            body: connector.jsonBody(body)
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Page created but could not parse response."
        }

        let pageId = json["id"] as? String ?? ""
        let url = json["url"] as? String ?? ""
        return "✅ Created Notion page: \(title)\n\(url)"
    }
}

// MARK: - Query Database Tool

final class QueryNotionDatabaseTool: Tool {
    var definition = ToolDefinition(
        id: "queryNotionDatabase",
        name: "Query Notion Database",
        description: "Query a Notion database and return results.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "databaseId", description: "Notion database ID", type: .string, required: true),
            ToolParameter(name: "filter", description: "Filter JSON (e.g. '{\"property\":\"Status\",\"status\":{\"equals\":\"Done\"}}')", type: .string, required: false),
            ToolParameter(name: "pageSize", description: "Results per page (default 10)", type: .integer, required: false)
        ])
    )

    private let connector: NotionConnector

    init(connector: NotionConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let databaseId = input["databaseId"], !databaseId.isEmpty else { return "No database ID specified." }

        var body: [String: Any] = [:]
        body["page_size"] = input["pageSiz"].flatMap(Int.init) ?? 10

        if let filterStr = input["filter"],
           let filterData = filterStr.data(using: .utf8),
           let filter = try? JSONSerialization.jsonObject(with: filterData) as? [String: Any] {
            body["filter"] = filter
        }

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "\(connector.baseURL)/databases/\(databaseId)/query",
            body: connector.jsonBody(body)
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return "No results."
        }

        if results.isEmpty { return "No matching pages found." }

        var output: [String] = []
        for page in results {
            let id = page["id"] as? String ?? ""
            let props = page["properties"] as? [String: Any] ?? [:]
            let titleValue = extractTitle(from: props)
            output.append("\(titleValue) (ID: \(id.prefix(8))...)")
        }
        return "Found \(results.count) pages:\n" + output.joined(separator: "\n")
    }

    private func extractTitle(from properties: [String: Any]) -> String {
        for (_, value) in properties {
            if let prop = value as? [String: Any],
               let type = prop["type"] as? String,
               type == "title",
               let titles = prop["title"] as? [[String: Any]],
               let first = titles.first,
               let text = first["plain_text"] as? String {
                return text
            }
        }
        return "(untitled)"
    }
}
