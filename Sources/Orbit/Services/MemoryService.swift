import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "memory")

final class MemoryService {
    private(set) var memoryStore: MemoryStore?
    private(set) var embeddingService: EmbeddingService?
    private(set) var contextBuilder: ContextBuilder?
    private(set) var consolidationService: MemoryConsolidationService?
    private(set) var kbService: KnowledgeBaseService?
    let summarizer = ConversationSummarizer()

    private let eventBus: EventBus
    private var useLocalEmbeddings = false

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func configure(database: OrbitDatabase, openAIKey: String, preferLocal: Bool = false, llmService: LLMService? = nil, enableCrossConversationMemory: Bool = true, auditService: AuditService? = nil) {
        let store = MemoryStore(db: database.db)
        memoryStore = store

        if let llmService {
            consolidationService = MemoryConsolidationService(store: store, llmService: llmService)
        }

        let embedder: EmbeddingService
        if preferLocal, let local = LocalEmbeddings() {
            embedder = local
            useLocalEmbeddings = true
            log.notice("Using local embeddings (NaturalLanguage)")
        } else {
            embedder = OpenAIEmbeddings(apiKey: openAIKey)
            useLocalEmbeddings = false
        }

        embeddingService = embedder
        let builder = ContextBuilder(memoryStore: store, embeddingService: embedder, auditService: auditService)
        builder.setCrossConversationMemoryEnabled(enableCrossConversationMemory)
        kbService.map { builder.kbService = $0 }
        contextBuilder = builder
    }

    func setKnowledgeBaseService(_ service: KnowledgeBaseService?) {
        kbService = service
        contextBuilder?.kbService = service
    }

    func startConsolidationIfNeeded() async {
        await consolidationService?.runIfNeeded()
    }

    func updateAPIKey(_ key: String) {
        guard !useLocalEmbeddings else { return }
        let embedder = OpenAIEmbeddings(apiKey: key)
        embeddingService = embedder
        if let store = memoryStore {
            contextBuilder = ContextBuilder(memoryStore: store, embeddingService: embedder)
        }
    }

    func contextMessages(query: String?, recentMessages: [Message], conversationId: String?, workspaceId: String? = nil, workspaceName: String? = nil, workspacePath: String? = nil, workspaceKBIds: [String]? = nil) async -> [LLMMessage] {
        var systemMessages = [LLMMessage]()

        if let wsName = workspaceName {
            var wsContext = "Active workspace: \(wsName)"
            if let wsPath = workspacePath {
                wsContext += " (path: \(wsPath))"
            }
            systemMessages.append(LLMMessage(role: .system, content: wsContext))
        }

        guard let convId = conversationId else {
            return systemMessages + recentMessages.suffix(6).map { msg in
                LLMMessage(role: msg.role == .assistant ? .assistant : .user, content: msg.content, images: msg.images)
            }
        }

        if let query, let builder = contextBuilder {
            builder.workspaceKBIds = workspaceKBIds
            let recent = Array(recentMessages.suffix(3))
            let context = await builder.build(conversationId: convId, query: query, recentMessages: recent, workspaceId: workspaceId)
            return systemMessages + context.messages
        }

        if contextBuilder == nil {
            log.warning("ContextBuilder not configured — returning recent messages only")
        }

        return systemMessages + recentMessages.suffix(6).map { msg in
            LLMMessage(role: msg.role == .assistant ? .assistant : .user, content: msg.content, images: msg.images)
        }
    }

    func storeExchange(messages: [Message], conversationId: String?) async {
        guard let store = memoryStore, let embedder = embeddingService,
              let convId = conversationId
        else { return }

        guard messages.count >= 2 else { return }
        guard let assistant = messages.last(where: { $0.role == .assistant }),
              let user = messages.last(where: { $0.role == .user })
        else { return }

        do {
            try await storeChunked(store: store, embedder: embedder, convId: convId, message: assistant, role: "assistant")
            try await storeChunked(store: store, embedder: embedder, convId: convId, message: user, role: "user")

            let messageCount = messages.count
            if messageCount > 0, messageCount % 10 == 0 {
                await updateSummary(conversationId: convId, messages: messages)
            }
            eventBus.publish(MemoryStoredEvent(conversationId: convId))
        } catch {
            log.warning("Failed to store memory: \(error.localizedDescription)")
        }
    }

    private func storeChunked(store: MemoryStore, embedder: EmbeddingService, convId: String, message: Message, role: String) async throws {
        let chunks = store.chunkContent(message.content)
        for chunk in chunks {
            let embedding = try? await embedder.embed(text: chunk.prefix(8000).trimmingCharacters(in: .whitespaces))
            try store.storeMessage(
                conversationId: convId, messageId: message.id.uuidString,
                role: role, content: chunk,
                embedding: embedding
            )
        }
    }

    private func updateSummary(conversationId: String, messages: [Message]) async {
        guard let store = memoryStore else { return }
        do {
            let existing = try store.getSummary(conversationId: conversationId)
            let provider = OpenAIProvider(apiKey: "")
            let summary: String
            if let existing {
                let newMessages = Array(messages.suffix(10))
                summary = try await summarizer.updateSummary(existing: existing, newMessages: newMessages, provider: provider)
            } else {
                summary = try await summarizer.summarize(messages: Array(messages), provider: provider)
            }
            try store.storeSummary(conversationId: conversationId, summary: summary, messageCount: messages.count)
        } catch {
            log.warning("Failed to update summary: \(error.localizedDescription)")
        }
    }
}
