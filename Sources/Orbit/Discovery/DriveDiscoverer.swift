import Foundation

final class DriveDiscoverer: Discoverer {
    let serviceName = "drive"
    private let connector: GoogleDriveConnector

    init(connector: GoogleDriveConnector) { self.connector = connector }

    func scan(store: DiscoveryStore, classification: ClassificationService) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []
        var invoices: [DiscoveredInvoice] = []

        let files = try await listFiles()
        for file in files {
            guard let id = file["id"] as? String,
                  let name = file["name"] as? String else { continue }
            let mimeType = file["mimeType"] as? String ?? ""
            let modified = file["modifiedTime"] as? String ?? ""
            let link = file["webViewLink"] as? String

            var content = ""
            if mimeType == "application/vnd.google-apps.document" || mimeType.contains("text") {
                if let text = try? await readFileContent(id: id, mimeType: mimeType) {
                    content = text
                }
            }

            let (entityType, summary) = await classification.classify(title: name, content: content) ?? (.document, name)

            switch entityType {
            case .invoice:
                let vendor = summary
                let dateStr = modified.prefix(10)
                invoices.append(DiscoveredInvoice(id: "drive_inv_\(id)", service: "drive", vendor: vendor, amount: 0, currency: "USD", invoiceDate: String(dateStr), dueDate: nil, isRecurring: false, sourceMessageId: nil, sourceFileId: id, discoveredAt: Date()))
            default:
                let parsedDate = parseDate(modified)
                documents.append(DiscoveredDocument(id: "drive_doc_\(id)", service: "drive", externalId: id, title: name, summary: summary, url: link, mimeType: mimeType, discoveredAt: Date(), updatedAt: parsedDate))
            }
        }

        for doc in documents { try? store.saveDocument(doc) }
        for inv in invoices { try? store.saveInvoice(inv) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: invoices)
    }

    func incrementalScan(store: DiscoveryStore, classification: ClassificationService, since: Date) async throws -> ScanResult {
        var documents: [DiscoveredDocument] = []
        var invoices: [DiscoveredInvoice] = []

        let files = try await listFiles()
        for file in files {
            guard let id = file["id"] as? String,
                  let name = file["name"] as? String else { continue }
            if store.document(externalId: id, service: "drive") != nil { continue }

            let mimeType = file["mimeType"] as? String ?? ""
            let link = file["webViewLink"] as? String
            let modified = file["modifiedTime"] as? String ?? ""

            var content = ""
            if mimeType == "application/vnd.google-apps.document" || mimeType.contains("text") {
                if let text = try? await readFileContent(id: id, mimeType: mimeType) { content = text }
            }

            let (entityType, summary) = await classification.classify(title: name, content: content) ?? (.document, name)
            switch entityType {
            case .invoice:
                invoices.append(DiscoveredInvoice(id: "drive_inv_\(id)", service: "drive", vendor: summary, amount: 0, currency: "USD", invoiceDate: String(modified.prefix(10)), dueDate: nil, isRecurring: false, sourceMessageId: nil, sourceFileId: id, discoveredAt: Date()))
            default:
                let parsedDate = parseDate(modified)
                documents.append(DiscoveredDocument(id: "drive_doc_\(id)", service: "drive", externalId: id, title: name, summary: summary, url: link, mimeType: mimeType, discoveredAt: Date(), updatedAt: parsedDate))
            }
        }

        for doc in documents { try? store.saveDocument(doc) }
        for inv in invoices { try? store.saveInvoice(inv) }

        return ScanResult(accounts: [], subscriptions: [], documents: documents, invoices: invoices)
    }

    // MARK: - Helpers

    private func listFiles() async throws -> [[String: Any]] {
        let (data, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/drive/v3/files?pageSize=100&fields=files(id,name,mimeType,modifiedTime,webViewLink)"
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return [] }
        return files
    }

    private func readFileContent(id: String, mimeType: String) async throws -> String? {
        if mimeType == "application/vnd.google-apps.document" {
            let (data, _) = try await connector.authenticatedRequest(
                url: "https://docs.googleapis.com/v1/documents/\(id)/export?mimeType=text/plain"
            )
            return String(data: data, encoding: .utf8)
        }
        let (data, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/drive/v3/files/\(id)?alt=media"
        )
        return String(data: data, encoding: .utf8)
    }

    private func parseDate(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: String(iso.prefix(19))) ?? Date()
    }
}
