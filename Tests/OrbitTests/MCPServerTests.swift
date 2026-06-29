import Testing
import Foundation
@testable import Orbit

private final class MCPTestTool: Tool {
    let definition = ToolDefinition(
        id: "test_tool",
        name: "Test Tool",
        description: "A test tool",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "input", description: "Input value", type: .string, required: true)
        ])
    )
    func run(input: [String: String]) async throws -> String {
        return "Hello, \(input["input"] ?? "world")!"
    }
}

private func makeServer() -> MCPServer {
    let registry = ToolRegistry()
    registry.register(MCPTestTool())
    return MCPServer(toolRegistry: registry)
}

// MARK: - Parse Errors

@Test func mcpParseErrorOnInvalidJSON() async {
    let server = makeServer()
    let result = await server.handleJSON("not json")
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect(resp["jsonrpc"] as? String == "2.0")
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32700)
    }
}

@Test func mcpParseErrorOnNonJsonRpc() async {
    let server = makeServer()
    let result = await server.handleJSON(#"{"jsonrpc":"1.0","id":1,"method":"test"}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32600)
    }
}

// MARK: - Initialize

@Test func mcpInitializeReturnsCapabilities() async {
    let server = makeServer()
    let result = await server.handleJSON(#"""
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
    """#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let res = resp["result"] as? [String: Any] {
        #expect(resp["jsonrpc"] as? String == "2.0")
        #expect(resp["id"] as? Int == 1)
        #expect(res["protocolVersion"] as? String == "2024-11-05")
        #expect((res["serverInfo"] as? [String: Any])?["name"] as? String == "Orbit")
        #expect((res["capabilities"] as? [String: Any])?["tools"] != nil)
    }
}

// MARK: - Tools List

@Test func mcpListToolsFailsBeforeInitialize() async {
    let server = makeServer()
    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32000)
    }
}

@Test func mcpListToolsAfterInitialize() async {
    let server = makeServer()
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#)
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let res = resp["result"] as? [String: Any],
       let tools = res["tools"] as? [[String: Any]] {
        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "test_tool")
        #expect(tools[0]["description"] as? String == "A test tool")
    }
}

// MARK: - Tool Call

@Test func mcpCallToolFailsBeforeInitialize() async {
    let server = makeServer()
    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"test_tool","arguments":{}}}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32000)
    }
}

@Test func mcpCallToolReturnsResult() async {
    let server = makeServer()
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#)
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"test_tool","arguments":{"input":"World"}}}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let res = resp["result"] as? [String: Any],
       let content = res["content"] as? [[String: Any]] {
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "Hello, World!")
    }
}

@Test func mcpCallToolReportsMissingTool() async {
    let server = makeServer()
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#)
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)

    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"nonexistent","arguments":{}}}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32602)
    }
}

// MARK: - Notifications

@Test func mcpNotificationReturnsNoResponse() async {
    let server = makeServer()
    let result = await server.handleJSON(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
    #expect(result == nil, "Notifications should not produce a response")
}

// MARK: - Unknown Method

@Test func mcpUnknownMethodReturnsError() async {
    let server = makeServer()
    _ = await server.handleJSON(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}"#)

    let result = await server.handleJSON(#"{"jsonrpc":"2.0","id":5,"method":"unknown_method"}"#)
    #expect(result != nil)
    if let data = result?.data(using: .utf8),
       let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        #expect((resp["error"] as? [String: Any])?["code"] as? Int == -32601)
    }
}
