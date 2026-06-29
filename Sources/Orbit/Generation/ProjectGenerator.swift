import Foundation

final class ProjectGenerator {
    private let fm = FileManager.default

    private var documentsURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
    }

    func generate(title: String, content: String) async throws -> URL {
        try fm.createDirectory(at: documentsURL, withIntermediateDirectories: true)

        let folderName = sanitizeFilename(from: title)
        let projectURL = documentsURL.appendingPathComponent(folderName)
        try fm.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let files = parseFiles(from: content)
        if files.isEmpty {
            let readmeURL = projectURL.appendingPathComponent("README.md")
            try content.write(to: readmeURL, atomically: true, encoding: .utf8)
        } else {
            for file in files {
                let fileURL = projectURL.appendingPathComponent(file.path)
                try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }

        return projectURL
    }

    private lazy var filePattern: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "^FILE:\\s*(.+)$", options: .caseInsensitive)
    }()

    private func parseFiles(from text: String) -> [(path: String, content: String)] {
        var files: [(String, String)] = []
        let lines = text.components(separatedBy: .newlines)
        var currentPath: String?
        var currentContent: [String] = []

        func flush() {
            guard let path = currentPath, !currentContent.isEmpty else { return }
            let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .newlines)
            files.append((path, content))
            currentContent = []
        }

        guard let pattern = filePattern else { return [] }
        for line in lines {
            if let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let pathRange = Range(match.range(at: 1), in: line) {
                flush()
                currentPath = String(line[pathRange]).trimmingCharacters(in: .whitespaces)
                continue
            }
            if currentPath != nil {
                currentContent.append(line)
            }
        }
        flush()

        return files
    }

    private func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }
}
