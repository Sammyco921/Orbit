import Foundation

struct SearchResults {
    let text: String
    let sources: [(title: String, url: String)]
}

final class WebBrowserEngine {
    private let scriptExecutor = ScriptExecutor()
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15"

    func search(_ query: String) async throws -> SearchResults {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchURL = "https://html.duckduckgo.com/html/?q=\(encoded)"

        let html = try await scriptExecutor.run(
            executable: "/usr/bin/curl",
            arguments: ["-sL", "--max-time", "15", "-H", "User-Agent: \(userAgent)", searchURL]
        )

        let sources = extractSources(from: html)
        let text = extractText(from: html)

        return SearchResults(text: text, sources: sources)
    }

    func fetchPage(url: String) async throws -> String {
        let html = try await scriptExecutor.run(
            executable: "/usr/bin/curl",
            arguments: ["-sL", "--max-time", "10", "-H", "User-Agent: \(userAgent)", url]
        )
        return extractText(from: html)
    }

    func extractSources(from html: String) -> [(title: String, url: String)] {
        var sources: [(String, String)] = []

        guard let pattern = try? NSRegularExpression(pattern: "<a rel=\"nofollow\" class=\"result__a\" href=\"([^\"]+)\">([^<]+)</a>")
        else { return sources }

        let range = NSRange(html.startIndex..., in: html)
        let matches = pattern.matches(in: html, range: range)

        for match in matches.prefix(8) {
            guard let urlRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html)
            else { continue }
            let rawURL = String(html[urlRange])
            let title = String(html[titleRange]).trimmingCharacters(in: .whitespaces)
            if let decoded = decodeDuckDuckGoURL(rawURL) {
                sources.append((title, decoded))
            }
        }

        return sources
    }

    private func decodeDuckDuckGoURL(_ raw: String) -> String? {
        guard let url = URL(string: raw),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let uddg = components.queryItems?.first { $0.name == "uddg" }?.value
        return uddg?.removingPercentEncoding ?? raw
    }

    func extractText(from html: String) -> String {
        var text = html

        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?<\\/script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?<\\/style>", with: "", options: .regularExpression)

        text = text.replacingOccurrences(of: "<br\\s*\\/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/tr>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/div>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<\\/h[1-6]>", with: "\n", options: .regularExpression)

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")

        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
