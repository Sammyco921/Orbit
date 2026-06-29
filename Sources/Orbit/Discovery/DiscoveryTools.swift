import Foundation

// MARK: - Index Tool

final class DiscoveryIndexTool: Tool {
    var definition = ToolDefinition(
        id: "discoveryIndex",
        name: "Discovery Index",
        description: "Index all connected services to discover accounts, subscriptions, documents, invoices, and projects. Runs a full scan across Gmail, Drive, GitHub, and Notion.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "mode", description: "Index mode: 'full' (re-scan everything) or 'incremental' (only new items since last index)", type: .string, required: false)
        ])
    )

    private let discoveryService: DiscoveryService

    init(discoveryService: DiscoveryService) {
        self.discoveryService = discoveryService
    }

    func run(input: [String: String]) async throws -> String {
        let mode = input["mode"] ?? "incremental"

        if mode == "full" {
            await discoveryService.runFullIndex()
        } else {
            await discoveryService.runIncrementalIndex()
        }

        let summary = await discoveryService.summary()
        return """
        Index complete.
        Accounts: \(summary.totalAccounts)
        Subscriptions: \(summary.totalSubscriptions)
        Documents: \(summary.totalDocuments)
        Invoices: \(summary.totalInvoices)
        Projects: \(summary.totalProjects)
        """
    }
}

// MARK: - Search Tool

final class DiscoverySearchTool: Tool {
    var definition = ToolDefinition(
        id: "discoverySearch",
        name: "Discovery Search",
        description: "Search across all discovered entities (accounts, subscriptions, documents, invoices, projects) from a single query.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Search query", type: .string, required: true)
        ])
    )

    private let searchService: SearchService

    init(searchService: SearchService) { self.searchService = searchService }

    func run(input: [String: String]) async throws -> String {
        guard let query = input["query"], !query.isEmpty else { return "No query specified." }
        let result = await searchService.search(query)

        if result.results.isEmpty {
            return "No results found for '\(query)'."
        }

        var output: [String] = ["Results for '\(query)':"]
        for r in result.results.prefix(20) {
            let icon: String
            switch r.entityType {
            case .account: icon = "👤"
            case .subscription: icon = "🔄"
            case .document: icon = "📄"
            case .invoice: icon = "🧾"
            case .project: icon = "📁"
            }
            output.append("\(icon) [\(r.source)] \(r.title)")
            if let s = r.summary { output.append("   \(s)") }
        }
        if result.results.count > 20 {
            output.append("... and \(result.results.count - 20) more")
        }
        return output.joined(separator: "\n")
    }
}

// MARK: - Summary Tool

final class DiscoverySummaryTool: Tool {
    var definition = ToolDefinition(
        id: "discoverySummary",
        name: "Discovery Summary",
        description: "Get a summary of all discovered entities — total accounts, subscriptions, documents, invoices, and projects indexed so far.",
        inputSchema: ToolSchema(parameters: [])
    )

    private let discoveryService: DiscoveryService

    init(discoveryService: DiscoveryService) { self.discoveryService = discoveryService }

    func run(input: [String: String]) async throws -> String {
        let summary = await discoveryService.summary()
        let lastIndexed = summary.lastIndexedAt.map { "Last indexed: \($0)" } ?? "Not yet indexed."

        return """
        Discovery Summary
        \(lastIndexed)
        Accounts: \(summary.totalAccounts)
        Subscriptions: \(summary.totalSubscriptions)
        Documents: \(summary.totalDocuments)
        Invoices: \(summary.totalInvoices)
        Projects: \(summary.totalProjects)
        """
    }
}

// MARK: - List Entities Tool

final class DiscoveryListTool: Tool {
    var definition = ToolDefinition(
        id: "discoveryList",
        name: "Discovery List",
        description: "List discovered entities of a specific type (accounts, subscriptions, documents, invoices, projects).",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "type", description: "Entity type: accounts, subscriptions, documents, invoices, projects", type: .string, required: true),
            ToolParameter(name: "service", description: "Filter by service (gmail, drive, github, notion). Optional.", type: .string, required: false)
        ])
    )

    private let discoveryService: DiscoveryService

    init(discoveryService: DiscoveryService) { self.discoveryService = discoveryService }

    func run(input: [String: String]) async throws -> String {
        guard let type = input["type"] else { return "No type specified." }
        let serviceFilter = input["service"]

        switch type {
        case "accounts":
            let accounts = await discoveryService.allAccounts()
            let filtered = serviceFilter.map { s in accounts.filter { $0.service == s } } ?? accounts
            if filtered.isEmpty { return "No accounts found." }
            return filtered.map { "\($0.accountName) (\($0.accountEmail ?? "no email")) on \($0.service)" }.joined(separator: "\n")

        case "subscriptions":
            let subs = await discoveryService.activeSubscriptions()
            let filtered = serviceFilter.map { s in subs.filter { $0.service == s } } ?? subs
            if filtered.isEmpty { return "No subscriptions found." }
            return filtered.map { sub in
                let amount = sub.amount.map { String(format: "$%.2f", $0) } ?? "unknown"
                return "\(sub.name) — \(amount)/\(sub.billingCycle ?? "mo") on \(sub.service)"
            }.joined(separator: "\n")

        case "documents":
            let docs: [DiscoveredDocument]
            if let s = serviceFilter {
                docs = await discoveryService.documents(service: s)
            } else {
                docs = await discoveryService.allDocuments()
            }
            if docs.isEmpty { return "No documents found." }
            return docs.map { doc in
                let link = doc.url ?? "(no link)"
                return "\(doc.title) (\(doc.service))\n  \(link)"
            }.joined(separator: "\n")

        case "invoices":
            let invs = await discoveryService.allInvoices()
            if invs.isEmpty { return "No invoices found." }
            return invs.map { inv in
                let recurring = inv.isRecurring ? " (recurring)" : ""
                return "\(inv.vendor) — \(String(format: "$%.2f", inv.amount)) on \(inv.invoiceDate)\(recurring)"
            }.joined(separator: "\n")

        case "projects":
            let projects = await discoveryService.allProjects()
            if projects.isEmpty { return "No projects found." }
            return projects.map { p in
                var s = p.name
                if let d = p.description { s += ": \(d)" }
                if !p.associatedRepos.isEmpty { s += "\n  Repos: \(p.associatedRepos.joined(separator: ", "))" }
                return s
            }.joined(separator: "\n---\n")

        default:
            return "Unknown type '\(type)'. Valid: accounts, subscriptions, documents, invoices, projects"
        }
    }
}
