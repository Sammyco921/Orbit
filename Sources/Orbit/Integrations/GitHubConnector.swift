import Foundation

final class GitHubConnector: APIConnector, Connector {
    let id = "github"
    let name = "GitHub"
    let requiredScopes = ["repo", "user"]
    var tools: [Tool] {
        [CreateIssueTool(connector: self), ListPRsTool(connector: self), SearchReposTool(connector: self), GetIssueTool(connector: self)]
    }

    var baseURL: String { "https://api.github.com" }
}

// MARK: - Create Issue Tool

final class CreateIssueTool: Tool {
    var definition = ToolDefinition(
        id: "createIssue",
        name: "Create GitHub Issue",
        description: "Create a new GitHub issue in a repository.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "repo", description: "Repository name (e.g. 'owner/repo')", type: .string, required: true),
            ToolParameter(name: "title", description: "Issue title", type: .string, required: true),
            ToolParameter(name: "body", description: "Issue body/description", type: .string, required: false),
            ToolParameter(name: "labels", description: "Comma-separated labels", type: .string, required: false)
        ])
    )

    private let connector: GitHubConnector

    init(connector: GitHubConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let repo = input["repo"], !repo.isEmpty else { return "No repository specified." }
        guard let title = input["title"], !title.isEmpty else { return "No title specified." }

        var body: [String: Any] = ["title": title]
        if let issueBody = input["body"] { body["body"] = issueBody }
        if let labelsStr = input["labels"] {
            body["labels"] = labelsStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "\(connector.baseURL)/repos/\(repo)/issues",
            body: connector.jsonBody(body)
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Issue created but could not parse response."
        }
        let number = json["number"] as? Int ?? 0
        let htmlURL = json["html_url"] as? String ?? ""
        return "✅ Created issue #\(number) in \(repo)\n\(htmlURL)"
    }
}

// MARK: - List PRs Tool

final class ListPRsTool: Tool {
    var definition = ToolDefinition(
        id: "listPRs",
        name: "List Pull Requests",
        description: "List open pull requests in a GitHub repository.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "repo", description: "Repository name (e.g. 'owner/repo')", type: .string, required: true),
            ToolParameter(name: "state", description: "PR state: 'open', 'closed', or 'all' (default: open)", type: .string, required: false)
        ])
    )

    private let connector: GitHubConnector

    init(connector: GitHubConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let repo = input["repo"], !repo.isEmpty else { return "No repository specified." }
        let state = input["state"] ?? "open"

        let (data, _) = try await connector.authenticatedRequest(
            url: "\(connector.baseURL)/repos/\(repo)/pulls?state=\(state)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return "Could not parse PR list."
        }

        if json.isEmpty { return "No \(state) pull requests in \(repo)." }

        var results: [String] = []
        for pr in json {
            let title = pr["title"] as? String ?? ""
            let number = pr["number"] as? Int ?? 0
            let user = (pr["user"] as? [String: Any])?["login"] as? String ?? "unknown"
            let url = pr["html_url"] as? String ?? ""
            results.append("#\(number): \(title) (by \(user))\n  \(url)")
        }
        return "Pull requests (\(state)) in \(repo):\n" + results.joined(separator: "\n")
    }
}

// MARK: - Search Repos Tool

final class SearchReposTool: Tool {
    var definition = ToolDefinition(
        id: "searchRepos",
        name: "Search Repositories",
        description: "Search GitHub repositories by query.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Search query", type: .string, required: true),
            ToolParameter(name: "maxResults", description: "Maximum results (default 5)", type: .integer, required: false)
        ])
    )

    private let connector: GitHubConnector

    init(connector: GitHubConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        let query = input["query"]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let maxResults = input["maxResult"].flatMap(Int.init) ?? 5

        let (data, _) = try await connector.authenticatedRequest(
            url: "\(connector.baseURL)/search/repositories?q=\(query)&per_page=\(maxResults)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return "No repositories found."
        }

        if items.isEmpty { return "No repositories match '\(input["query"] ?? "")'." }

        var results: [String] = []
        for repo in items {
            let name = repo["full_name"] as? String ?? ""
            let desc = repo["description"] as? String ?? "(no description)"
            let stars = repo["stargazers_count"] as? Int ?? 0
            let url = repo["html_url"] as? String ?? ""
            results.append("\(name) ⭐\(stars)\n  \(desc)\n  \(url)")
        }
        return results.joined(separator: "\n---\n")
    }
}

// MARK: - Get Issue Tool

final class GetIssueTool: Tool {
    var definition = ToolDefinition(
        id: "getIssue",
        name: "Get GitHub Issue",
        description: "Get details of a specific GitHub issue.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "repo", description: "Repository name (e.g. 'owner/repo')", type: .string, required: true),
            ToolParameter(name: "issueNumber", description: "Issue number", type: .integer, required: true)
        ])
    )

    private let connector: GitHubConnector

    init(connector: GitHubConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let repo = input["repo"], !repo.isEmpty else { return "No repository specified." }
        guard let number = input["issueNumber"].flatMap(Int.init) else { return "No issue number specified." }

        let (data, _) = try await connector.authenticatedRequest(
            url: "\(connector.baseURL)/repos/\(repo)/issues/\(number)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Could not parse issue."
        }

        let title = json["title"] as? String ?? ""
        let state = json["state"] as? String ?? ""
        let body = json["body"] as? String ?? "(no body)"
        let user = (json["user"] as? [String: Any])?["login"] as? String ?? "unknown"
        let comments = json["comments"] as? Int ?? 0
        let url = json["html_url"] as? String ?? ""

        return """
        #\(number): \(title) [\(state)]
        by \(user) | \(comments) comments
        \(url)
        ---
        \(body.prefix(5000))
        """
    }
}
