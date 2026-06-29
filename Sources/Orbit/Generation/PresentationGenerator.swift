import Foundation

final class PresentationGenerator {
    private let fm = FileManager.default

    private var documentsURL: URL {
        fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Orbit/Artifacts")
    }

    func generate(title: String, content: String) async throws -> URL {
        try fm.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        let filename = sanitizeFilename(from: title) + ".md"
        let outputURL = documentsURL.appendingPathComponent(filename)
        let formatted = formatPresentation(content, fallbackTitle: title)
        try formatted.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func formatPresentation(_ markdown: String, fallbackTitle: String) -> String {
        let slides = parseSlides(from: markdown, fallbackTitle: fallbackTitle)
        return slides.map { "## \($0.title)\n\n\($0.body)" }.joined(separator: "\n\n---\n\n")
    }

    private func parseSlides(from markdown: String, fallbackTitle: String) -> [(title: String, body: String)] {
        var slides: [(String, String)] = []
        var currentTitle = ""
        var currentBody: [String] = []

        let lines = markdown.components(separatedBy: .newlines)

        for line in lines {
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                if !currentTitle.isEmpty {
                    slides.append((currentTitle, currentBody.joined(separator: "\n")))
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                currentTitle = trimHeadingPrefix(trimmed)
                currentBody = []
            } else {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    currentBody.append(trimmed)
                }
            }
        }

        if !currentTitle.isEmpty {
            slides.append((currentTitle, currentBody.joined(separator: "\n")))
        }

        if slides.isEmpty {
            slides.append((fallbackTitle, markdown))
        }

        return slides
    }

    private func trimHeadingPrefix(_ line: String) -> String {
        guard let firstChar = line.first, firstChar == "#" else { return line }
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" {
            idx = line.index(after: idx)
        }
        return line[idx...].trimmingCharacters(in: .whitespaces)
    }

    private func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }
}
