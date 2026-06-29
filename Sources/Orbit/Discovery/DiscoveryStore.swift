import Foundation
import GRDB

final class DiscoveryStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) { self.db = db }

    // MARK: - Accounts

    func saveAccount(_ account: DiscoveredAccount) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO discovered_accounts (id, service, accountName, accountEmail, accountURL, sourceMessageId, discoveredAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [account.id, account.service, account.accountName, account.accountEmail, account.accountURL, account.sourceMessageId, account.discoveredAt.timeIntervalSince1970])
        }
    }

    func allAccounts() -> [DiscoveredAccount] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_accounts ORDER BY discoveredAt DESC").map(accountFromRow)
        }) ?? []
    }

    func accounts(service: String) -> [DiscoveredAccount] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_accounts WHERE service = ? ORDER BY discoveredAt DESC", arguments: [service]).map(accountFromRow)
        }) ?? []
    }

    // MARK: - Subscriptions

    func saveSubscription(_ sub: DiscoveredSubscription) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO discovered_subscriptions (id, service, name, amount, currency, billingCycle, nextBillingDate, sourceMessageId, discoveredAt, isActive)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [sub.id, sub.service, sub.name, sub.amount, sub.currency, sub.billingCycle, sub.nextBillingDate, sub.sourceMessageId, sub.discoveredAt.timeIntervalSince1970, sub.isActive ? 1 : 0])
        }
    }

    func allSubscriptions() -> [DiscoveredSubscription] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_subscriptions ORDER BY amount DESC").map(subFromRow)
        }) ?? []
    }

    func activeSubscriptions() -> [DiscoveredSubscription] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_subscriptions WHERE isActive = 1 ORDER BY amount DESC").map(subFromRow)
        }) ?? []
    }

    // MARK: - Documents

    func saveDocument(_ doc: DiscoveredDocument) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO discovered_documents (id, service, externalId, title, summary, url, mimeType, discoveredAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [doc.id, doc.service, doc.externalId, doc.title, doc.summary, doc.url, doc.mimeType, doc.discoveredAt.timeIntervalSince1970, doc.updatedAt.timeIntervalSince1970])
        }
    }

    func allDocuments() -> [DiscoveredDocument] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_documents ORDER BY updatedAt DESC").map(docFromRow)
        }) ?? []
    }

    func documents(service: String) -> [DiscoveredDocument] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_documents WHERE service = ? ORDER BY updatedAt DESC", arguments: [service]).map(docFromRow)
        }) ?? []
    }

    func document(externalId: String, service: String) -> DiscoveredDocument? {
        (try? db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM discovered_documents WHERE externalId = ? AND service = ?", arguments: [externalId, service]).map(docFromRow)
        })
    }

    // MARK: - Invoices

    func saveInvoice(_ inv: DiscoveredInvoice) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO discovered_invoices (id, service, vendor, amount, currency, invoiceDate, dueDate, isRecurring, sourceMessageId, sourceFileId, discoveredAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [inv.id, inv.service, inv.vendor, inv.amount, inv.currency, inv.invoiceDate, inv.dueDate, inv.isRecurring ? 1 : 0, inv.sourceMessageId, inv.sourceFileId, inv.discoveredAt.timeIntervalSince1970])
        }
    }

    func invoices(dateRange: (start: String, end: String)? = nil) -> [DiscoveredInvoice] {
        (try? db.read { db in
            if let (start, end) = dateRange {
                return try Row.fetchAll(db, sql: "SELECT * FROM discovered_invoices WHERE invoiceDate >= ? AND invoiceDate <= ? ORDER BY invoiceDate DESC", arguments: [start, end]).map(invFromRow)
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM discovered_invoices ORDER BY invoiceDate DESC").map(invFromRow)
        }) ?? []
    }

    // MARK: - Projects

    func saveProject(_ project: DiscoveredProject) throws {
        let reposJSON = (try? JSONEncoder().encode(project.associatedRepos)).map { String(data: $0, encoding: .utf8) } ?? "[]"
        let docsJSON = (try? JSONEncoder().encode(project.associatedDocs)).map { String(data: $0, encoding: .utf8) } ?? "[]"
        let emailsJSON = (try? JSONEncoder().encode(project.associatedEmails)).map { String(data: $0, encoding: .utf8) } ?? "[]"

        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO discovered_projects (id, name, description, associatedReposJSON, associatedDocsJSON, associatedEmailsJSON, discoveredAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [project.id, project.name, project.description, reposJSON, docsJSON, emailsJSON, project.discoveredAt.timeIntervalSince1970])
        }
    }

    func allProjects() -> [DiscoveredProject] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_projects ORDER BY discoveredAt DESC").map(projectFromRow)
        }) ?? []
    }

    // MARK: - Search

    func search(_ query: String) -> [DiscoverySearchResult] {
        let pattern = "%\(query)%"
        var results: [DiscoverySearchResult] = []

        // Search documents
        let docs = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_documents WHERE title LIKE ? OR summary LIKE ? LIMIT 10", arguments: [pattern, pattern])
        }) ?? []
        results.append(contentsOf: docs.map { row in
            DiscoverySearchResult(entityType: .document, title: row["title"], summary: row["summary"], source: row["service"], url: row["url"], score: 1.0, entityID: row["id"])
        })

        // Search subscriptions
        let subs = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_subscriptions WHERE name LIKE ? LIMIT 10", arguments: [pattern])
        }) ?? []
        results.append(contentsOf: subs.map { row in
            DiscoverySearchResult(entityType: .subscription, title: row["name"], summary: nil, source: row["service"], url: nil, score: 0.9, entityID: row["id"])
        })

        // Search accounts
        let accts = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_accounts WHERE accountName LIKE ? OR accountEmail LIKE ? LIMIT 10", arguments: [pattern, pattern])
        }) ?? []
        results.append(contentsOf: accts.map { row in
            DiscoverySearchResult(entityType: .account, title: row["accountName"], summary: row["accountEmail"], source: row["service"], url: row["accountURL"], score: 0.8, entityID: row["id"])
        })

        // Search invoices
        let invs = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_invoices WHERE vendor LIKE ? LIMIT 10", arguments: [pattern])
        }) ?? []
        results.append(contentsOf: invs.map { row in
            DiscoverySearchResult(entityType: .invoice, title: row["vendor"], summary: nil, source: row["service"], url: nil, score: 0.7, entityID: row["id"])
        })

        // Search projects
        let projs = (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM discovered_projects WHERE name LIKE ? OR description LIKE ? LIMIT 10", arguments: [pattern, pattern])
        }) ?? []
        results.append(contentsOf: projs.map { row in
            DiscoverySearchResult(entityType: .project, title: row["name"], summary: row["description"], source: "local", url: nil, score: 1.5, entityID: row["id"])
        })

        return results.sorted { $0.score > $1.score }
    }

    // MARK: - Summary

    func summary() -> DiscoverySummary {
        let acctCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM discovered_accounts") }) ?? 0
        let subCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM discovered_subscriptions") }) ?? 0
        let docCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM discovered_documents") }) ?? 0
        let invCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM discovered_invoices") }) ?? 0
        let projCount = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM discovered_projects") }) ?? 0
        let lastTimestamp = try? db.read { try Double.fetchOne($0, sql: "SELECT MAX(discoveredAt) FROM discovered_documents") ?? 0 }
        let lastIndexed = lastTimestamp.map { Date(timeIntervalSince1970: $0) }

        return DiscoverySummary(totalAccounts: acctCount, totalSubscriptions: subCount, totalDocuments: docCount, totalInvoices: invCount, totalProjects: projCount, lastIndexedAt: lastIndexed)
    }

    // MARK: - Row Mappers

    private func accountFromRow(_ row: Row) -> DiscoveredAccount {
        DiscoveredAccount(id: row["id"], service: row["service"], accountName: row["accountName"], accountEmail: row["accountEmail"], accountURL: row["accountURL"], sourceMessageId: row["sourceMessageId"], discoveredAt: Date(timeIntervalSince1970: row["discoveredAt"]))
    }

    private func subFromRow(_ row: Row) -> DiscoveredSubscription {
        DiscoveredSubscription(id: row["id"], service: row["service"], name: row["name"], amount: row["amount"], currency: row["currency"], billingCycle: row["billingCycle"], nextBillingDate: row["nextBillingDate"], sourceMessageId: row["sourceMessageId"], discoveredAt: Date(timeIntervalSince1970: row["discoveredAt"]), isActive: (row["isActive"] as? Int) == 1)
    }

    private func docFromRow(_ row: Row) -> DiscoveredDocument {
        DiscoveredDocument(id: row["id"], service: row["service"], externalId: row["externalId"], title: row["title"], summary: row["summary"], url: row["url"], mimeType: row["mimeType"], discoveredAt: Date(timeIntervalSince1970: row["discoveredAt"]), updatedAt: Date(timeIntervalSince1970: row["updatedAt"]))
    }

    private func invFromRow(_ row: Row) -> DiscoveredInvoice {
        DiscoveredInvoice(id: row["id"], service: row["service"], vendor: row["vendor"], amount: row["amount"], currency: row["currency"], invoiceDate: row["invoiceDate"], dueDate: row["dueDate"], isRecurring: (row["isRecurring"] as? Int) == 1, sourceMessageId: row["sourceMessageId"], sourceFileId: row["sourceFileId"], discoveredAt: Date(timeIntervalSince1970: row["discoveredAt"]))
    }

    private func projectFromRow(_ row: Row) -> DiscoveredProject {
        let repos: [String] = decodeJSON(row["associatedReposJSON"], fallback: [String]())
        let docs: [String] = decodeJSON(row["associatedDocsJSON"], fallback: [String]())
        let emails: [String] = decodeJSON(row["associatedEmailsJSON"], fallback: [String]())
        return DiscoveredProject(id: row["id"], name: row["name"], description: row["description"], associatedRepos: repos, associatedDocs: docs, associatedEmails: emails, discoveredAt: Date(timeIntervalSince1970: row["discoveredAt"]))
    }

    private func decodeJSON<T: Codable>(_ value: String?, fallback: [T]) -> [T] {
        guard let data = value?.data(using: .utf8), let arr = try? JSONDecoder().decode([T].self, from: data) else { return fallback }
        return arr
    }
}
