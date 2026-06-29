import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "research")

final class ResearchEngine {
    private let webEngine = WebBrowserEngine()

    func fetchWebContent(query: String) async throws -> String {
        let results = try await webEngine.search(query)
        var output = results.text
        if !results.sources.isEmpty {
            output += "\n\n---\nSources:"
            for (i, source) in results.sources.enumerated() {
                output += "\n[\(i + 1)] \(source.title) — \(source.url)"
            }
        }
        return output
    }

    func fetchWithSources(query: String) async throws -> SearchResults {
        try await webEngine.search(query)
    }

    func searchWithPageContent(query: String) async throws -> String {
        let results = try await webEngine.search(query)
        var output = results.text

        if let first = results.sources.first {
            output += "\n\n---\nFull Page: \(first.title)"
            do {
                let pageContent = try await webEngine.fetchPage(url: first.url)
                let truncated = String(pageContent.prefix(8000))
                output += "\n\(truncated)"
            } catch {
                log.warning("Failed to fetch full page: \(error.localizedDescription)")
                output += "\n(Page content unavailable)"
            }
            output += "\n\n---\nOther Sources:"
            for (i, source) in results.sources.enumerated() {
                output += "\n[\(i + 1)] \(source.title) — \(source.url)"
            }
        } else if !results.sources.isEmpty {
            output += "\n\n---\nSources:"
            for (i, source) in results.sources.enumerated() {
                output += "\n[\(i + 1)] \(source.title) — \(source.url)"
            }
        }

        return output
    }

    func deepSearch(query: String, provider: LLMProvider) async throws -> String {
        let initial = try await webEngine.search(query)
        var combinedText = initial.text
        var allSources = initial.sources

        let subtopicsPrompt = """
        Based on this research query, identify 3-5 specific subtopics or angles that would be worth exploring further.
        Return ONLY a comma-separated list of subtopic search queries, nothing else.

        Query: \(query)
        """

        let subtopicsResponse = try await provider.complete(messages: [
            LLMMessage(role: .system, content: subtopicsPrompt)
        ])

        let subtopicQueries = subtopicsResponse
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'.")) }
            .filter { !$0.isEmpty }
            .prefix(3)

        try await withThrowingTaskGroup(of: (query: String, results: SearchResults?).self) { group in
            for subtopic in subtopicQueries {
                group.addTask {
                    let results = try? await self.webEngine.search(subtopic)
                    return (subtopic, results)
                }
            }
            for try await (subtopic, subResults) in group {
                if let subResults {
                    combinedText += "\n\n---\nSubtopic: \(subtopic)\n\(subResults.text)"
                    allSources.append(contentsOf: subResults.sources)
                } else {
                    log.warning("Sub-topic search failed for '\(subtopic)'")
                    combinedText += "\n\n_Sub-topic search for '\(subtopic)' failed_"
                }
            }
        }

        var deduplicated = allSources
        var seen = Set<String>()
        deduplicated.removeAll { !seen.insert($0.url).inserted }

        var result = combinedText
        if !deduplicated.isEmpty {
            result += "\n\n---\nSources:"
            for (i, source) in deduplicated.enumerated() {
                result += "\n[\(i + 1)] \(source.title) — \(source.url)"
            }
        }

        return result
    }

    func extractFacts(from text: String, provider: LLMProvider) async throws -> String {
        try await provider.complete(messages: [
            LLMMessage(role: .system, content: """
                Extract key facts from the following research content into structured notes.
                Organize by topic. Include specific numbers, dates, names, and statistics.
                Use markdown with headings and bullet points.
                """),
            LLMMessage(role: .user, content: text)
        ])
    }
}
