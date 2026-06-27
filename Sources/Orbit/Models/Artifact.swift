import Foundation

struct Artifact: Identifiable, Codable {
    let id: UUID
    let filename: String
    let type: ArtifactType
    let content: String
    let fileURL: URL?

    enum ArtifactType: String, Codable, CaseIterable {
        case markdown
        case spreadsheet
        case presentation
        case document
        case pdf
        case folder
        case code
    }

    init(filename: String, type: ArtifactType, content: String, fileURL: URL? = nil) {
        self.id = UUID()
        self.filename = filename
        self.type = type
        self.content = content
        self.fileURL = fileURL
    }
}
