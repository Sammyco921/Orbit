import Foundation

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var icon: String
    var path: String?
    var knowledgeBaseIds: [String]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, icon: String = "folder", path: String? = nil, knowledgeBaseIds: [String] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.path = path
        self.knowledgeBaseIds = knowledgeBaseIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
