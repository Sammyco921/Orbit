import Foundation

final class ArtifactGenerator {
    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
    }

    func generate(description: String, provider: LLMProvider) async throws -> Artifact {
        let content = try await provider.complete(messages: [
            LLMMessage(role: .system, content: """
                You are a content generator. Create high-quality content based on the request.
                Return the content in plain text with markdown formatting.
                """),
            LLMMessage(role: .user, content: description)
        ])

        let filename = sanitizeFilename(from: description)
        let artifact = Artifact(
            filename: "\(filename).md",
            type: .markdown,
            content: content
        )

        return artifact
    }

    func generateSpreadsheet(description: String, provider: LLMProvider) async throws -> Artifact {
        let content = try await provider.complete(messages: [
            LLMMessage(role: .system, content: """
                You are a spreadsheet content generator. Create CSV-formatted data based on the request.
                Include headers in the first row. Use commas as delimiters.
                Return ONLY the CSV data, no explanation.
                """),
            LLMMessage(role: .user, content: description)
        ])

        let filename = sanitizeFilename(from: description)
        let artifact = Artifact(
            filename: "\(filename).csv",
            type: .spreadsheet,
            content: content
        )

        return artifact
    }

    func saveToDisk(_ artifact: Artifact) throws -> URL {
        let directory = documentsURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(artifact.filename)
        try artifact.content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    func saveToDisk(filename: String, content: String) throws -> URL {
        let directory = documentsURL
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent(filename)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }

    private func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }
}
