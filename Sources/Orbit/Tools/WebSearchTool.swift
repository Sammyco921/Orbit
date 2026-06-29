import Foundation

final class WebSearchTool: Tool {
    var definition = ToolDefinition(
        id: "webSearch",
        name: "Web Search",
        description: "Search the web for information and return results with page content",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "The search query", type: .string, required: true)
        ])
    )

    var researchService: ResearchService?

    func run(input: [String: String]) async throws -> String {
        guard let query = input["query"], !query.isEmpty else {
            return "No search query provided."
        }
        guard let service = researchService else {
            return "Research service not available."
        }
        let result = try await service.searchWithPageContent(query: query)
        return result
    }
}

final class DeepResearchTool: Tool {
    var definition = ToolDefinition(
        id: "deepResearch",
        name: "Deep Research",
        description: "Perform an in-depth multi-source research on a topic, combining web searches with AI analysis",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "The research topic or question", type: .string, required: true)
        ])
    )

    var researchService: ResearchService?
    var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let query = input["query"], !query.isEmpty else {
            return "No research query provided."
        }
        guard let service = researchService else {
            return "Research service not available."
        }
        guard let llm = llmService else {
            return "LLM service not available."
        }
        let provider = llm.currentProvider()
        let result = try await service.deepSearch(query: query, provider: provider)
        return result
    }
}
