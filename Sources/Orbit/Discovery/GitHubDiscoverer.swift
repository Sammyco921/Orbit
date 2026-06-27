import Foundation

final class GitHubDiscoverer: Discoverer {
    let serviceName = "github"
    private let connector: GitHubConnector

    init(connector: GitHubConnector) { self.connector = connector }

    func scan(store: DiscoveryStore, classification: ClassificationService) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []
        var projects: [DiscoveredProject] = []

        let repos = try await listRepos()
        for repo in repos {
            guard let name = repo["full_name"] as? String,
                  let id = repo["id"] as? Int else { continue }
            let description = repo["description"] as? String
            let url = repo["html_url"] as? String

            documents.append(DiscoveredDocument(
                id: "gh_repo_\(id)", service: "github", externalId: "\(id)", title: name,
                summary: description, url: url, mimeType: "application/github.repository",
                discoveredAt: Date(), updatedAt: Date()
            ))

            projects.append(DiscoveredProject(
                id: "gh_project_\(id)", name: name, description: description,
                associatedRepos: [name], associatedDocs: [], associatedEmails: [],
                discoveredAt: Date()
            ))
        }

        for doc in documents { try? store.saveDocument(doc) }
        for project in projects { try? store.saveProject(project) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: [])
    }

    func incrementalScan(store: DiscoveryStore, classification: ClassificationService, since: Date) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []
        var projects: [DiscoveredProject] = []

        let repos = try await listRepos()
        for repo in repos {
            guard let name = repo["full_name"] as? String,
                  let id = repo["id"] as? Int else { continue }

            // Only include repos updated since last scan
            if let pushed = repo["pushed_at"] as? String {
                let f = ISO8601DateFormatter()
                if let date = f.date(from: pushed), date < since { continue }
            }

            let description = repo["description"] as? String
            let url = repo["html_url"] as? String

            documents.append(DiscoveredDocument(
                id: "gh_repo_\(id)", service: "github", externalId: "\(id)", title: name,
                summary: description, url: url, mimeType: "application/github.repository",
                discoveredAt: Date(), updatedAt: Date()
            ))
            projects.append(DiscoveredProject(
                id: "gh_project_\(id)", name: name, description: description,
                associatedRepos: [name], associatedDocs: [], associatedEmails: [],
                discoveredAt: Date()
            ))
        }

        for doc in documents { try? store.saveDocument(doc) }
        for project in projects { try? store.saveProject(project) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: [])
    }

    // MARK: - Helpers

    private func listRepos() async throws -> [[String: Any]] {
        let (data, _) = try await connector.authenticatedRequest(
            url: "\(connector.baseURL)/user/repos?per_page=100&sort=updated"
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return json
    }
}
