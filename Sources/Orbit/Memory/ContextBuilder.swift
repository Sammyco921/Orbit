import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "context")

struct BuiltContext {
    let messages: [LLMMessage]
    let summary: String?
    let sourceCount: Int
}

final class ContextBuilder {
    private let memoryStore: MemoryStore
    private let embeddingService: EmbeddingService
    private let auditService: AuditService?
    private var enableCrossConversation: Bool = true
    var kbService: KnowledgeBaseService?
    var workspaceKBIds: [String]?

    init(memoryStore: MemoryStore, embeddingService: EmbeddingService, auditService: AuditService? = nil) {
        self.memoryStore = memoryStore
        self.embeddingService = embeddingService
        self.auditService = auditService
    }

    func setCrossConversationMemoryEnabled(_ enabled: Bool) {
        enableCrossConversation = enabled
    }

    func build(conversationId: String, query: String, recentMessages: [Message], workspaceId: String? = nil) async -> BuiltContext {
        var contextMessages = [LLMMessage]()

        let summary = try? memoryStore.getSummary(conversationId: conversationId)
        if let summary {
            contextMessages.append(LLMMessage(role: .system, content: "[Conversation context so far: \(summary)]"))
        }

        if enableCrossConversation {
            var profileLines: [String] = []
            if let prefs = try? memoryStore.getAllPreferences(), !prefs.isEmpty {
                profileLines.append("User preferences:")
                for (k, v) in prefs { profileLines.append("- \(k): \(v)") }
            }
            if let facts = try? memoryStore.getUserFacts(), !facts.isEmpty {
                profileLines.append("\nLearned facts about user:")
                for f in facts where f.confidence > 0.3 {
                    profileLines.append("- \(f.fact) (confidence: \(String(format: "%.0f", f.confidence * 100))%)")
                }
            }
            if let auditService {
                let toolStats = auditService.toolUsageStats()
                if !toolStats.isEmpty {
                    profileLines.append("\nMost used tools:")
                    for t in toolStats.prefix(5) {
                        profileLines.append("- \(t.toolName): used \(t.count) times, \(String(format: "%.0f", t.successRate * 100))% success")
                    }
                }
            }
            if !profileLines.isEmpty {
                contextMessages.append(LLMMessage(role: .system, content: "[User profile:\n\(profileLines.joined(separator: "\n"))]"))
            }
        }

        let recentIds = Set(recentMessages.map { $0.id.uuidString })
        do {
            let queryEmbedding = try await embeddingService.embed(text: query)
            let similar = try memoryStore.hybridSearch(
                embedding: queryEmbedding, query: query, limit: 5,
                conversationId: conversationId, workspaceId: workspaceId,
                semanticWeight: 0.6
            )
            for item in similar where !recentIds.contains(item.messageId ?? "") {
                let role: LLMMessage.Role = item.role == "assistant" ? .assistant : .user
                contextMessages.append(LLMMessage(role: role, content: item.content))
            }

            if enableCrossConversation {
                let globalItems = try memoryStore.searchGlobalItems(limit: 3)
                for item in globalItems {
                    contextMessages.append(LLMMessage(role: .system, content: "[Global memory: \(item.content)]"))
                }
            }

            if enableCrossConversation, let kbService = kbService, let kbIds = workspaceKBIds, !kbIds.isEmpty {
                let kbResults = try await kbService.search(query: query, kbIds: kbIds, limit: 3)
                for (item, _) in kbResults {
                    let source = item.filePath.map { " (\($0))" } ?? ""
                    contextMessages.append(LLMMessage(role: .system, content: "[Knowledge base\(source): \(item.content)]"))
                }
            }
        } catch {
            log.warning("Semantic search unavailable: \(error.localizedDescription)")
        }

        for msg in recentMessages {
            let role: LLMMessage.Role = msg.role == .assistant ? .assistant : .user
            contextMessages.append(LLMMessage(role: role, content: msg.content, images: msg.images))
        }

        return BuiltContext(messages: contextMessages, summary: summary, sourceCount: contextMessages.count)
    }
}
