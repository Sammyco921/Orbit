import Foundation

final class NotionDiscoverer: Discoverer {
    let serviceName = "notion"
    private let connector: NotionConnector

    init(connector: NotionConnector) { self.connector = connector }

    func scan(store: DiscoveryStore, classification: ClassificationService) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []

        let pages = try await searchPages()
        for page in pages {
            guard let id = page["id"] as? String else { continue }
            let props = page["properties"] as? [String: Any] ?? [:]
            let title = extractTitle(from: props)
            let url = page["url"] as? String

            documents.append(DiscoveredDocument(
                id: "notion_doc_\(id)", service: "notion", externalId: id, title: title,
                summary: nil, url: url, mimeType: "application/notion.page",
                discoveredAt: Date(), updatedAt: Date()
            ))
        }

        for doc in documents { try? store.saveDocument(doc) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: [])
    }

    func incrementalScan(store: DiscoveryStore, classification: ClassificationService, since: Date) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []

        let pages = try await searchPages()
        for page in pages {
            guard let id = page["id"] as? String else { continue }
            if store.document(externalId: id, service: "notion") != nil { continue }

            let props = page["properties"] as? [String: Any] ?? [:]
            let title = extractTitle(from: props)
            let url = page["url"] as? String

            documents.append(DiscoveredDocument(
                id: "notion_doc_\(id)", service: "notion", externalId: id, title: title,
                summary: nil, url: url, mimeType: "application/notion.page",
                discoveredAt: Date(), updatedAt: Date()
            ))
        }

        for doc in documents { try? store.saveDocument(doc) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: [])
    }

    // MARK: - Helpers

    private func searchPages() async throws -> [[String: Any]] {
        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "\(connector.baseURL)/search",
            body: try? JSONSerialization.data(withJSONObject: ["page_size": 100])
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.filter { ($0["object"] as? String) == "page" }
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
