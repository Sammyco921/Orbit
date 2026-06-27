import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "memory-manager-agent")

/// Agent that manages memory consolidation, fact extraction, and pruning
final class MemoryManagerAgent: Agent {
    private let runtime: OrbitRuntime

    init(name: String, runtime: OrbitRuntime) {
        self.runtime = runtime
        super.init(
            name: name,
            type: .memoryManager,
            capabilities: [
                AgentCapability(name: "memory_consolidation", description: "Summarizes and compresses old memories"),
                AgentCapability(name: "fact_extraction", description: "Extracts facts from conversations"),
                AgentCapability(name: "memory_pruning", description: "Removes outdated or irrelevant memories"),
                AgentCapability(name: "preference_learning", description: "Learns user preferences from interactions")
            ]
        )
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        // Extract facts and insights from the provided context
        let result = try await extractFacts(from: context)
        return result
    }

    private func extractFacts(from context: AgentTaskContext) async throws -> String {
        // Use the LLM to extract facts from relevant messages
        let relevantText = context.relevantMessages.joined(separator: "\n")
        guard !relevantText.isEmpty else { return "No messages to extract facts from." }

        let prompt = """
        Extract key facts, preferences, and patterns from the following conversation history.
        Focus on:
        - User preferences (e.g., "prefers concise answers", "likes dark mode")
        - Frequently used tools or patterns
        - Important information about projects or goals
        - Recurring themes or interests

        Conversation history:
        \(relevantText)

        Respond with a bullet list of extracted facts.
        """

        let provider = runtime.llmService.currentProvider()
        let messages = [LLMMessage(role: .user, content: prompt)]
        return try await provider.complete(messages: messages, parameters: .init(temperature: 0.3))
    }
}
