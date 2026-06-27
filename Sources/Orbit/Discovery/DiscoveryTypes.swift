import Foundation

// MARK: - Entity Types

struct DiscoveredAccount: Codable, Sendable, Identifiable {
    let id: String
    let service: String
    let accountName: String
    let accountEmail: String?
    let accountURL: String?
    let sourceMessageId: String?
    let discoveredAt: Date
}

struct DiscoveredSubscription: Codable, Sendable, Identifiable {
    let id: String
    let service: String
    let name: String
    let amount: Double?
    let currency: String?
    let billingCycle: String?
    let nextBillingDate: String?
    let sourceMessageId: String?
    let discoveredAt: Date
    let isActive: Bool
}

struct DiscoveredDocument: Codable, Sendable, Identifiable {
    let id: String
    let service: String
    let externalId: String
    let title: String
    let summary: String?
    let url: String?
    let mimeType: String?
    let discoveredAt: Date
    let updatedAt: Date
}

struct DiscoveredInvoice: Codable, Sendable, Identifiable {
    let id: String
    let service: String
    let vendor: String
    let amount: Double
    let currency: String
    let invoiceDate: String
    let dueDate: String?
    let isRecurring: Bool
    let sourceMessageId: String?
    let sourceFileId: String?
    let discoveredAt: Date
}

struct DiscoveredProject: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let associatedRepos: [String]
    let associatedDocs: [String]
    let associatedEmails: [String]
    let discoveredAt: Date
}

// MARK: - Search Result

struct DiscoverySearchResult: Sendable {
    let entityType: DiscoveryEntityType
    let title: String
    let summary: String?
    let source: String
    let url: String?
    let score: Double
    let entityID: String
}

enum DiscoveryEntityType: String, Sendable, Codable {
    case account
    case subscription
    case document
    case invoice
    case project
}

// MARK: - Aggregation

struct DiscoverySummary: Sendable {
    let totalAccounts: Int
    let totalSubscriptions: Int
    let totalDocuments: Int
    let totalInvoices: Int
    let totalProjects: Int
    let lastIndexedAt: Date?
}
