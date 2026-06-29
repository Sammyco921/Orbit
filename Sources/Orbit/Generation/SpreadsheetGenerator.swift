import Foundation

final class SpreadsheetGenerator {
    private let fm = FileManager.default

    private var documentsURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
    }

    func generate(title: String, csvContent: String) async throws -> URL {
        try fm.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        let filename = sanitizeFilename(from: title) + ".csv"
        let outputURL = documentsURL.appendingPathComponent(filename)
        try csvContent.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }
}
