import Foundation

struct ScanResult {
    let accounts: [DiscoveredAccount]
    let subscriptions: [DiscoveredSubscription]
    let documents: [DiscoveredDocument]
    let invoices: [DiscoveredInvoice]
}

protocol Discoverer: Sendable {
    var serviceName: String { get }
    func scan(store: DiscoveryStore, classification: ClassificationService) async throws -> ScanResult
    func incrementalScan(store: DiscoveryStore, classification: ClassificationService, since: Date) async throws -> ScanResult
}
