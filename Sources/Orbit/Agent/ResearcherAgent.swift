import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "researcher-agent")

/// Agent that specializes in research: web search, knowledge base search, and fact extraction
final class ResearcherAgent: Agent {
    private let runtime: OrbitRuntime

    init(name: String, runtime: OrbitRuntime) {
        self.runtime = runtime
        super.init(
            name: name,
            type: .researcher,
            capabilities: [
                AgentCapability(name: "web_search", description: "Searches the web for information"),
                AgentCapability(name: "knowledge_base_search", description: "Searches knowledge bases for relevant documents"),
                AgentCapability(name: "fact_extraction", description: "Extracts and synthesizes facts from search results"),
                AgentCapability(name: "deep_research", description: "Multi-step research with follow-up queries")
            ]
        )
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        let researchService = runtime.researchService
        let provider = runtime.llmService.currentProvider()

        do {
            // Try deep search first (multi-step research with LLM synthesis)
            let result = try await researchService.deepSearch(query: goal, provider: provider)
            return result
        } catch {
            log.error("Deep search failed: \(error.localizedDescription)")
        }

        do {
            // Fall back to basic web search
            let result = try await researchService.searchWithPageContent(query: goal)
            return result
        } catch {
            log.error("Basic search failed: \(error.localizedDescription)")
        }

        // Last resort: LLM knowledge only
        let prompt = """
        Research goal: \(goal)
        Context: \(context.relevantMessages.joined(separator: "\n"))

        No web search results were available. Based on your existing knowledge, provide a comprehensive answer.
        """

        let messages = [LLMMessage(role: .user, content: prompt)]
        return try await provider.complete(messages: messages, parameters: .init(temperature: 0.3))
    }
}
