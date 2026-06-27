import Foundation
import Testing
@testable import Orbit

struct OrbitAPITests {

    @Test func testHTTPRequestParsing() {
        let raw = "GET /api/tools HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer test123\r\n\r\n"
        guard let request = HTTPRequest.parse(raw.data(using: .utf8)!) else {
            Issue.record("Failed to parse HTTP request")
            return
        }
        #expect(request.method == "GET")
        #expect(request.path == "/api/tools")
        #expect(request.headers["host"] == "localhost")
        #expect(request.headers["authorization"] == "Bearer test123")
    }

    @Test func testHTTPRequestWithBody() {
        let body = #"{"name":"test"}"#
        let raw = "POST /api/tools/call HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        guard let request = HTTPRequest.parse(raw.data(using: .utf8)!) else {
            Issue.record("Failed to parse POST request")
            return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/api/tools/call")
        #expect(request.bodyString == body)
    }

    @Test func testHTTPRequestMissingMethod() {
        let raw = "invalid-request"
        let request = HTTPRequest.parse(raw.data(using: .utf8)!)
        #expect(request == nil)
    }

    @Test func testAuth() {
        let api = OrbitAPI()
        api.configure(runtime: nil, apiKey: "secret123")
        let authed = HTTPRequest.parse(Data("GET /api/health HTTP/1.1\r\nAuthorization: Bearer secret123\r\n\r\n".utf8))!
        let unauthed = HTTPRequest.parse(Data("GET /api/health HTTP/1.1\r\n\r\n".utf8))!

        #expect(api.authenticateForTest(authed))
        #expect(!api.authenticateForTest(unauthed))
    }

    @Test func testHealthEndpoint() async throws {
        let api = OrbitAPI()
        api.configure(runtime: nil, apiKey: "test-key-123")
        try api.start(port: 0)
        guard await api.waitForReady() else {
            Issue.record("API server did not become ready")
            api.stop()
            return
        }
        defer { api.stop() }

        let url = URL(string: "http://127.0.0.1:\(api.port)/api/health")!
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer test-key-123", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: urlRequest)
        let httpResp = try #require(resp as? HTTPURLResponse)
        #expect(httpResp.statusCode == 200)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"status\""))
    }
}

extension OrbitAPI {
    func authenticateForTest(_ request: HTTPRequest) -> Bool {
        guard let auth = request.headers["authorization"] else { return false }
        return auth == "Bearer \(apiKey)"
    }
}
