import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "research")

protocol ResearchServiceProtocol {
    func fetchWebContent(query: String) async throws -> String
    func fetchWithSources(query: String) async throws -> SearchResults
    func searchWithPageContent(query: String) async throws -> String
    func deepSearch(query: String, provider: LLMProvider) async throws -> String
    func extractFacts(from text: String, provider: LLMProvider) async throws -> String
}

final class ResearchService: ResearchServiceProtocol {
    private let engine = ResearchEngine()

    func fetchWebContent(query: String) async throws -> String {
        try await engine.fetchWebContent(query: query)
    }

    func fetchWithSources(query: String) async throws -> SearchResults {
        try await engine.fetchWithSources(query: query)
    }

    func searchWithPageContent(query: String) async throws -> String {
        try await engine.searchWithPageContent(query: query)
    }

    func deepSearch(query: String, provider: LLMProvider) async throws -> String {
        try await engine.deepSearch(query: query, provider: provider)
    }

    func extractFacts(from text: String, provider: LLMProvider) async throws -> String {
        try await engine.extractFacts(from: text, provider: provider)
    }
}
