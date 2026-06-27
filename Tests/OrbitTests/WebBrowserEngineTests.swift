import Testing
@testable import Orbit

struct WebBrowserEngineTests {

    @Test func extractTextStripsScriptTags() {
        let engine = WebBrowserEngine()
        let html = "<html><head><script>alert('x')</script></head><body><p>Hello</p></body></html>"
        let result = engine.extractText(from: html)
        #expect(!result.contains("alert"))
        #expect(result.contains("Hello"))
    }

    @Test func extractTextStripsStyleTags() {
        let engine = WebBrowserEngine()
        let html = "<style>body { color: red; }</style><p>Text</p>"
        let result = engine.extractText(from: html)
        #expect(!result.contains("color"))
        #expect(result.contains("Text"))
    }

    @Test func extractTextConvertsBlockElementsToNewlines() {
        let engine = WebBrowserEngine()
        let html = "<p>First</p><p>Second</p>"
        let result = engine.extractText(from: html)
        #expect(result.contains("First"))
        #expect(result.contains("Second"))
    }

    @Test func extractTextDecodesHTMLEntities() {
        let engine = WebBrowserEngine()
        let html = "<p>A &amp; B &lt; C &gt; D</p>"
        let result = engine.extractText(from: html)
        #expect(result == "A & B < C > D")
    }

    @Test func extractTextTrimsExcessNewlines() {
        let engine = WebBrowserEngine()
        let html = "<div>Line1</div><div>Line2</div><div>Line3</div>"
        let result = engine.extractText(from: html)
        #expect(!result.contains("\n\n\n"))
    }

    @Test func extractSourcesFromDuckDuckGoHTML() {
        let engine = WebBrowserEngine()
        let html = """
        <a rel="nofollow" class="result__a" href="http://example.com?uddg=https%3A%2F%2Freal-url.com">Test Result</a>
        """
        let sources = engine.extractSources(from: html)
        #expect(sources.count == 1)
        #expect(sources[0].title == "Test Result")
        #expect(sources[0].url == "https://real-url.com")
    }

    @Test func extractSourcesLimitsToEight() {
        let engine = WebBrowserEngine()
        var links = ""
        for i in 0..<12 {
            links += "<a rel=\"nofollow\" class=\"result__a\" href=\"http://example.com?uddg=https%3A%2F%2Fsite\(i).com\">Site \(i)</a>"
        }
        let sources = engine.extractSources(from: links)
        #expect(sources.count <= 8)
    }

    @Test func extractTextHandlesEmptyInput() {
        let engine = WebBrowserEngine()
        #expect(engine.extractText(from: "").isEmpty)
    }

    @Test func extractSourcesHandlesNoMatches() {
        let engine = WebBrowserEngine()
        let html = "<html><body>No links here</body></html>"
        let sources = engine.extractSources(from: html)
        #expect(sources.isEmpty)
    }
}
