import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "search")

struct UnifiedSearchResult: Sendable {
    let query: String
    let results: [DiscoverySearchResult]
}

actor SearchService {
    private let discoveryService: DiscoveryService

    init(discoveryService: DiscoveryService) {
        self.discoveryService = discoveryService
    }

    func search(_ query: String) async -> UnifiedSearchResult {
        // Run discovery index search
        let localResults = await discoveryService.search(query)

        return UnifiedSearchResult(query: query, results: localResults)
    }

    // MARK: - Natural Language Queries

    func interpretAndSearch(_ naturalQuery: String) async -> UnifiedSearchResult {
        let keywords = extractKeywords(naturalQuery)
        let result = await search(keywords)
        return result
    }

    private func extractKeywords(_ query: String) -> String {
        let stopWords = Set(["my", "all", "the", "a", "an", "for", "of", "in", "on", "at", "to", "from", "with", "and", "or", "me", "i", "what", "where", "how", "show", "find", "get", "list", "give", "tell", "any", "every", "latest", "recent", "this", "that", "across", "related"])
        let words = query.lowercased().split(separator: " ").filter { !stopWords.contains(String($0)) && $0.count > 1 }
        return words.joined(separator: " ")
    }
}
