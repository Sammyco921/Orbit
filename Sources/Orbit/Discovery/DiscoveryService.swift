import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "discovery")

actor DiscoveryService {
    private let store: DiscoveryStore
    private let classification: ClassificationService
    private(set) var discoverers: [String: Discoverer] = [:]
    private var indexedServiceIDs: Set<String> = []
    private var lastIndexedAt: Date?

    init(store: DiscoveryStore, classification: ClassificationService) {
        self.store = store
        self.classification = classification
    }

    func registerDiscoverer(_ discoverer: Discoverer) {
        discoverers[discoverer.serviceName] = discoverer
    }

    // MARK: - Full Index

    func runFullIndex() async {
        log.notice("Starting full discovery index...")
        var totalAccounts = 0, totalSubs = 0, totalDocs = 0, totalInvs = 0

        for (name, discoverer) in discoverers {
            do {
                let result = try await discoverer.scan(store: store, classification: classification)
                totalAccounts += result.accounts.count
                totalSubs += result.subscriptions.count
                totalDocs += result.documents.count
                totalInvs += result.invoices.count
                log.notice("Indexed \(name): \(result.accounts.count) accounts, \(result.subscriptions.count) subs, \(result.documents.count) docs, \(result.invoices.count) invoices")
            } catch {
                log.warning("Failed to index \(name): \(error.localizedDescription)")
            }
        }

        indexedServiceIDs = Set(discoverers.keys)
        lastIndexedAt = Date()
        log.notice("Full index complete: \(totalAccounts) accounts, \(totalSubs) subscriptions, \(totalDocs) documents, \(totalInvs) invoices")
    }

    // MARK: - Incremental Index

    func runIncrementalIndex() async {
        let since = lastIndexedAt ?? Date.distantPast
        log.notice("Starting incremental discovery since \(since)...")

        for (name, discoverer) in discoverers {
            // If never indexed, do full scan
            if !indexedServiceIDs.contains(name) {
                do {
                    let result = try await discoverer.scan(store: store, classification: classification)
                    log.notice("Incremental indexed \(name) (full): \(result.accounts.count + result.subscriptions.count + result.documents.count + result.invoices.count) items")
                } catch {
                    log.warning("Incremental index failed for \(name): \(error.localizedDescription)")
                }
                indexedServiceIDs.insert(name)
                continue
            }

            do {
                let result = try await discoverer.incrementalScan(store: store, classification: classification, since: since)
                log.notice("Incremental indexed \(name): \(result.accounts.count + result.subscriptions.count + result.documents.count + result.invoices.count) new items")
            } catch {
                log.warning("Incremental index failed for \(name): \(error.localizedDescription)")
            }
        }

        lastIndexedAt = Date()
    }

    // MARK: - Query

    func search(_ query: String) -> [DiscoverySearchResult] {
        store.search(query)
    }

    func summary() -> DiscoverySummary {
        store.summary()
    }

    func allAccounts() -> [DiscoveredAccount] { store.allAccounts() }
    func allSubscriptions() -> [DiscoveredSubscription] { store.allSubscriptions() }
    func activeSubscriptions() -> [DiscoveredSubscription] { store.activeSubscriptions() }
    func allDocuments() -> [DiscoveredDocument] { store.allDocuments() }
    func documents(service: String) -> [DiscoveredDocument] { store.documents(service: service) }
    func allInvoices() -> [DiscoveredInvoice] { store.invoices() }
    func invoicesInRange(start: String, end: String) -> [DiscoveredInvoice] { store.invoices(dateRange: (start, end)) }
    func allProjects() -> [DiscoveredProject] { store.allProjects() }

    var isIndexed: Bool { !indexedServiceIDs.isEmpty }
}
