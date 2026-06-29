import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "reviewer-agent")

/// Agent that reviews output for quality, correctness, and completeness
final class ReviewerAgent: Agent {
    private let runtime: OrbitRuntime

    init(name: String, runtime: OrbitRuntime) {
        self.runtime = runtime
        super.init(
            name: name,
            type: .reviewer,
            capabilities: [
                AgentCapability(name: "quality_review", description: "Reviews output for quality and correctness"),
                AgentCapability(name: "fact_checking", description: "Verifies factual accuracy"),
                AgentCapability(name: "code_review", description: "Reviews code for bugs, style, and security issues"),
                AgentCapability(name: "completeness_check", description: "Checks if all requirements have been met")
            ]
        )
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        // Determine what to review from the goal
        let prompt = """
        Review the following output for quality, correctness, and completeness.

        Review goal: \(goal)
        Output to review: \(context.relevantMessages.joined(separator: "\n"))
        Additional context: \(context.additionalInstructions ?? "None")

        Provide a structured review with:
        1. Summary of what was reviewed
        2. Issues found (if any)
        3. Suggestions for improvement (if any)
        4. Overall verdict: APPROVED, APPROVED_WITH_CHANGES, or NEEDS_REWORK
        """

        let provider = runtime.llmService.currentProvider()
        let messages = [LLMMessage(role: .user, content: prompt)]
        return try await provider.complete(messages: messages, parameters: .init(temperature: 0.2))
    }
}
