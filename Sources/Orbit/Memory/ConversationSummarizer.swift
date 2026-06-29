import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "summarizer")

final class ConversationSummarizer {
    /// Generate an initial summary for a set of messages.
    func summarize(messages: [Message], provider: LLMProvider) async throws -> String {
        let conversationText = messages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
        return try await provider.complete(messages: [
            LLMMessage(role: .system, content: "Summarize the following conversation in 2-3 sentences. Capture the key topics, questions, and decisions made."),
            LLMMessage(role: .user, content: conversationText)
        ])
    }

    /// Update an existing summary with new messages.
    func updateSummary(existing: String, newMessages: [Message], provider: LLMProvider) async throws -> String {
        let newText = newMessages.map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
        return try await provider.complete(messages: [
            LLMMessage(role: .system, content: "Current conversation summary:\n\(existing)\n\nUpdate this summary to include the new messages below. Keep it 2-3 sentences."),
            LLMMessage(role: .user, content: newText)
        ])
    }
}
