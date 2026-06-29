import Foundation

/// A conversation containing an ordered list of messages, scoped to an optional workspace.
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var hasGeneratedTitle: Bool
    var modelConfig: ModelConfig?
    var isArchived: Bool
    var workspaceId: UUID?

    init(id: UUID = UUID(), title: String = "New Chat", messages: [Message] = [], createdAt: Date = Date(), updatedAt: Date = Date(), isPinned: Bool = false, hasGeneratedTitle: Bool = false, modelConfig: ModelConfig? = nil, isArchived: Bool = false, workspaceId: UUID? = nil) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.hasGeneratedTitle = hasGeneratedTitle
        self.modelConfig = modelConfig
        self.isArchived = isArchived
        self.workspaceId = workspaceId
    }

    enum CodingKeys: CodingKey {
        case id, title, messages, createdAt, updatedAt, isPinned, hasGeneratedTitle, modelConfig, isArchived, workspaceId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.messages = try container.decode([Message].self, forKey: .messages)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.hasGeneratedTitle = try container.decodeIfPresent(Bool.self, forKey: .hasGeneratedTitle) ?? false
        self.modelConfig = try container.decodeIfPresent(ModelConfig.self, forKey: .modelConfig)
        self.isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        self.workspaceId = try container.decodeIfPresent(UUID.self, forKey: .workspaceId)
    }
}
