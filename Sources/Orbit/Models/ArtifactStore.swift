import Foundation
import AppKit

struct ArtifactItem: Identifiable {
    let id: UUID
    let fileURL: URL
    var filename: String { fileURL.lastPathComponent }
    let type: Artifact.ArtifactType?
    let fileSize: Int64
    let createdAt: Date
    let conversationTitle: String?
    let conversationID: UUID?

    var sizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

final class ArtifactStore {
    private let fm = FileManager.default
    private var artifactsURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
    }

    func scan(conversations: [Conversation]) -> [ArtifactItem] {
        guard fm.fileExists(atPath: artifactsURL.path) else { return [] }

        let enumerator = fm.enumerator(
            at: artifactsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var items: [ArtifactItem] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir == false
            else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            let createdAt = resourceValues?.creationDate ?? Date()

            let type = artifactType(for: fileURL)
            let (convTitle, convID) = findSourceConversation(for: fileURL, conversations: conversations)

            items.append(ArtifactItem(
                id: UUID(),
                fileURL: fileURL,
                type: type,
                fileSize: fileSize,
                createdAt: createdAt,
                conversationTitle: convTitle,
                conversationID: convID
            ))
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func delete(_ item: ArtifactItem) throws {
        try fm.trashItem(at: item.fileURL, resultingItemURL: nil)
    }

    func revealInFinder(_ item: ArtifactItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
    }

    func open(_ item: ArtifactItem) {
        NSWorkspace.shared.open(item.fileURL)
    }

    private func artifactType(for url: URL) -> Artifact.ArtifactType? {
        switch url.pathExtension.lowercased() {
        case "md": .markdown
        case "csv", "xlsx", "numbers": .spreadsheet
        case "pptx", "key": .presentation
        case "docx", "pages": .document
        case "pdf": .pdf
        default: nil
        }
    }

    private func findSourceConversation(for fileURL: URL, conversations: [Conversation]) -> (String?, UUID?) {
        for conv in conversations {
            for msg in conv.messages {
                if msg.artifacts.contains(where: { $0.fileURL == fileURL }) {
                    return (conv.title, conv.id)
                }
            }
        }
        return (nil, nil)
    }
}
