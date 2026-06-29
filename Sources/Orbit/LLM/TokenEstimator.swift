import Foundation

/// Rough token estimator (~4 chars per token for English text).
/// Used to prevent context overflow without a real tokenizer.
enum TokenEstimator {
    static func estimateTokenCount(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    static func estimateTokenCount(_ messages: [LLMMessage]) -> Int {
        messages.reduce(0) { $0 + estimateTokenCount($1.content) + 4 }
    }

    /// Truncate messages to fit within `maxTokens`, keeping the most recent.
    static func truncateMessages(_ messages: [LLMMessage], maxTokens: Int = 128_000) -> [LLMMessage] {
        var total = 0
        var truncated = [LLMMessage]()
        // Always keep system messages
        let systemMessages = messages.filter { $0.role == .system }
        let nonSystem = messages.filter { $0.role != .system }

        for msg in systemMessages {
            total += estimateTokenCount(msg.content) + 4
            if total > maxTokens { break }
            truncated.append(msg)
        }

        // Keep most recent non-system messages, drop from the middle
        for msg in nonSystem.suffix(50) {
            let tokens = estimateTokenCount(msg.content) + 4
            if total + tokens > maxTokens { break }
            total += tokens
            truncated.append(msg)
        }

        return truncated
    }
}
