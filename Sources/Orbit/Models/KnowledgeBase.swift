import Foundation

struct KnowledgeBase: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var description: String?
    var sourceType: String  // "file", "folder", "repo", "url"
    var sourcePath: String?
    var createdAt: TimeInterval
    var updatedAt: TimeInterval

    init(id: String = UUID().uuidString, name: String, description: String? = nil, sourceType: String, sourcePath: String? = nil, createdAt: TimeInterval = Date().timeIntervalSince1970, updatedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.id = id
        self.name = name
        self.description = description
        self.sourceType = sourceType
        self.sourcePath = sourcePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
