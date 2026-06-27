import Foundation
import AppKit
import UniformTypeIdentifiers
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "conversation")

/// Manages conversation and message CRUD, persistence, active session tracking, and import/export.
final class ConversationService {
    private(set) var conversations: [Conversation] = []
    private(set) var activeConversationId: UUID? {
        didSet {
            if let id = activeConversationId {
                UserDefaults.standard.set(id.uuidString, forKey: "activeConversationId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeConversationId")
            }
        }
    }
    private let eventBus: EventBus

    private weak var database: OrbitDatabase?
    private weak var llmService: LLMService?

    init(eventBus: EventBus) {
        self.eventBus = eventBus
    }

    func configure(database: OrbitDatabase, llmService: LLMService) {
        self.database = database
        self.llmService = llmService
    }

    func loadConversations() {
        guard let db = database else {
            conversations = []
            activeConversationId = nil
            return
        }
        do {
            conversations = try db.loadAllConversations()
            // Restore active conversation from UserDefaults, fall back to last
            if let savedId = UserDefaults.standard.string(forKey: "activeConversationId"),
               let uuid = UUID(uuidString: savedId),
               conversations.contains(where: { $0.id == uuid }) {
                activeConversationId = uuid
            } else {
                activeConversationId = conversations.last?.id
            }
            log.debug("Loaded \(self.conversations.count) conversations from SQLite")
        } catch {
            log.error("Failed to load conversations: \(error.localizedDescription)")
            conversations = []
            activeConversationId = nil
        }
    }

    func saveConversations() {
        guard let db = database, let convId = activeConversationId,
              let conv = conversations.first(where: { $0.id == convId }) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try db.incrementalSave(conversation: conv)
            } catch {
                log.error("Failed to persist conversation: \(error.localizedDescription)")
            }
        }
    }

    func saveImmediately() {
        guard let db = database, let convId = activeConversationId,
              let conv = conversations.first(where: { $0.id == convId }) else { return }
        do {
            try db.incrementalSave(conversation: conv)
        } catch {
            log.error("Failed to persist conversation: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func createConversation(workspaceId: UUID? = nil) -> Conversation {
        let conversation = Conversation(workspaceId: workspaceId)
        conversations.append(conversation)
        activeConversationId = conversation.id
        saveConversations()
        eventBus.publish(ConversationCreatedEvent(id: conversation.id, title: conversation.title))
        return conversation
    }

    func selectConversation(_ id: UUID) {
        activeConversationId = id
    }

    func renameConversation(_ id: UUID, title: String) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].title = title
        saveConversations()
    }

    func togglePin(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isPinned.toggle()
        saveConversations()
    }

    func archiveConversation(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isArchived = true
        saveConversations()
    }

    func unarchiveConversation(_ id: UUID) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].isArchived = false
        saveConversations()
    }

    func moveConversation(_ id: UUID, toWorkspaceId: UUID?) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        conversations[index].workspaceId = toWorkspaceId
        saveConversations()
    }

    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            if let first = conversations.first {
                activeConversationId = first.id
            } else {
                activeConversationId = nil
                _ = createConversation()
            }
        }
        saveConversations()
        eventBus.publish(ConversationDeletedEvent(id: id))
    }

    var messages: [Message] {
        conversations.first(where: { $0.id == activeConversationId })?.messages ?? []
    }

    func conversation(for id: UUID) -> Conversation? {
        conversations.first(where: { $0.id == id })
    }

    @discardableResult
    func addMessage(_ message: Message) -> Int? {
        guard let index = conversations.firstIndex(where: { $0.id == activeConversationId }) else { return nil }
        conversations[index].messages.append(message)
        conversations[index].updatedAt = Date()
        updateTitle(for: index)
        saveConversations()
        if let convId = activeConversationId {
            eventBus.publish(MessageAddedEvent(conversationId: convId, message: message))
        }
        return index
    }

    func deleteMessage(_ id: UUID) {
        guard let convIndex = conversations.firstIndex(where: { $0.id == activeConversationId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == id })
        else { return }
        conversations[convIndex].messages.removeSubrange(msgIndex...)
        conversations[convIndex].updatedAt = Date()
        saveConversations()
    }

    func editMessage(_ id: UUID, newContent: String) -> Int? {
        guard let convIndex = conversations.firstIndex(where: { $0.id == activeConversationId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == id })
        else { return nil }
        conversations[convIndex].messages[msgIndex].content = newContent
        conversations[convIndex].messages.removeSubrange((msgIndex + 1)...)
        conversations[convIndex].updatedAt = Date()
        saveConversations()
        return msgIndex
    }

    func forkConversation(at messageId: UUID) -> Conversation? {
        guard let convIndex = conversations.firstIndex(where: { $0.id == activeConversationId }),
              let msgIndex = conversations[convIndex].messages.firstIndex(where: { $0.id == messageId })
        else { return nil }
        let messagesUpTo = Array(conversations[convIndex].messages[...msgIndex])
        let forked = Conversation(title: conversations[convIndex].title + " (fork)", messages: messagesUpTo)
        conversations.append(forked)
        activeConversationId = forked.id
        saveConversations()
        return forked
    }

    func exportConversation(_ id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let convData = try? encoder.encode(conversation),
              let convJSON = try? JSONSerialization.jsonObject(with: convData) as? [String: Any]
        else { return }
        let wrapper: [String: Any] = ["version": 1, "conversation": convJSON]
        guard let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }

        let panel = NSSavePanel()
        panel.title = "Export Conversation"
        panel.nameFieldStringValue = "\(conversation.title).orbit.json"
        panel.allowedContentTypes = [UTType.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    func importConversation(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["version"] is Int,
              let convData = try? JSONSerialization.data(withJSONObject: json["conversation"] as Any),
              let conversation = try? JSONDecoder().decode(Conversation.self, from: convData)
        else { return }
        conversations.append(conversation)
        activeConversationId = conversation.id
        saveConversations()
    }

    private func updateTitle(for index: Int) {
        let conversation = conversations[index]
        guard conversation.title == "New Chat", !conversation.hasGeneratedTitle else { return }
        let msgs = conversation.messages
        guard msgs.count >= 2 else { return }

        let firstUserMsg = msgs.first(where: { $0.role == .user })?.content ?? ""
        let firstResponse = msgs.first(where: { $0.role == .assistant })?.content ?? ""
        let preview = String(firstResponse.prefix(500))

        conversations[index].hasGeneratedTitle = true
        saveConversations()

        guard let llm = llmService?.currentProvider() else { return }

        Task {
            do {
                let title = try await llm.complete(messages: [
                    LLMMessage(role: .system, content: "Generate a very short title (3-6 words) for this conversation based on the user's request and your response. Return ONLY the title, no quotes, no explanation."),
                    LLMMessage(role: .user, content: "Request: \(String(firstUserMsg.prefix(300)))\n\nResponse: \(preview)")
                ])
                let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
                guard !cleaned.isEmpty else { return }
                await MainActor.run {
                    guard index < self.conversations.count else { return }
                    self.conversations[index].title = String(cleaned.prefix(60))
                    self.saveConversations()
                }
            } catch {
                let trimmed = String(firstUserMsg.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
                await MainActor.run {
                    guard index < self.conversations.count else { return }
                    self.conversations[index].title = trimmed + (firstUserMsg.count > 60 ? "..." : "")
                }
            }
        }
    }
}
