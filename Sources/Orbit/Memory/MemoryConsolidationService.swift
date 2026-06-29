import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "consolidation")

final class MemoryConsolidationService {
    private let store: MemoryStore
    private let llmService: LLMService
    private let summarizer = ConversationSummarizer()

    private let consolidationInterval: TimeInterval = 7 * 86400 // 7 days
    private let minItemsForConsolidation = 10

    private var lastConsolidationKey = "lastMemoryConsolidationDate"

    init(store: MemoryStore, llmService: LLMService) {
        self.store = store
        self.llmService = llmService
    }

    func runIfNeeded() async {
        let lastRun = UserDefaults.standard.double(forKey: lastConsolidationKey)
        let now = Date().timeIntervalSince1970
        guard now - lastRun > consolidationInterval else { return }

        do {
            try await consolidate()
            UserDefaults.standard.set(now, forKey: lastConsolidationKey)
        } catch {
            log.warning("Consolidation failed: \(error.localizedDescription)")
        }
    }

    private func consolidate() async throws {
        let cutoff = Date().timeIntervalSince1970 - 30 * 86400 // 30 days old

        struct ConvGroup {
            let conversationId: String
            var items: [(id: String, content: String)]
        }

        let rows = try store.getAllItems()
        var groups: [String: ConvGroup] = [:]
        for item in rows where item.createdAt < cutoff && item.type != MemoryType.summary.rawValue {
            var group = groups[item.conversationId] ?? ConvGroup(conversationId: item.conversationId, items: [])
            group.items.append((item.id, item.content))
            groups[item.conversationId] = group
        }

        for (_, group) in groups where group.items.count >= minItemsForConsolidation {
            let provider = llmService.currentProvider()
            let conversationText = group.items.map { $0.content }.joined(separator: "\n\n")
            do {
                let summary = try await provider.complete(messages: [
                    LLMMessage(role: .system, content: "Summarize the following conversation history in 2-3 sentences. Capture key topics, decisions, and user preferences."),
                    LLMMessage(role: .user, content: conversationText)
                ])
                try store.storeMessage(
                    conversationId: group.conversationId,
                    messageId: UUID().uuidString,
                    role: "system",
                    content: summary,
                    embedding: nil,
                    type: .summary
                )
                let idsToDelete = group.items.map { $0.id }
                try store.deleteItems(ids: idsToDelete)
                log.notice("Consolidated \(group.items.count) items for conversation \(group.conversationId)")
            } catch {
                log.warning("Failed to consolidate conversation \(group.conversationId): \(error.localizedDescription)")
            }
        }
    }
}
