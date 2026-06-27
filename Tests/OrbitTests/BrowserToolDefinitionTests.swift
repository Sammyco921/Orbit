import Testing
import Foundation
import GRDB
@testable import Orbit

struct BrowserToolDefinitionTests {

    @Test func navigateToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = NavigateTool(runtime: runtime)
        #expect(tool.definition.id == "browserNavigate")
        #expect(tool.definition.inputSchema.parameters.count == 1)
        #expect(tool.definition.inputSchema.parameters[0].name == "url")
        #expect(tool.definition.inputSchema.parameters[0].required == true)
    }

    @Test func clickToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = ClickTool(runtime: runtime)
        #expect(tool.definition.id == "browserClick")
        #expect(tool.definition.inputSchema.parameters.count == 1)
        #expect(tool.definition.inputSchema.parameters[0].name == "selector")
    }

    @Test func typeToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = TypeTool(runtime: runtime)
        #expect(tool.definition.id == "browserType")
        #expect(tool.definition.inputSchema.parameters.count == 2)
        #expect(tool.definition.inputSchema.parameters[0].name == "selector")
        #expect(tool.definition.inputSchema.parameters[1].name == "text")
    }

    @Test func extractToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = ExtractTool(runtime: runtime)
        #expect(tool.definition.id == "browserExtract")
        #expect(tool.definition.inputSchema.parameters.count == 1)
        #expect(tool.definition.inputSchema.parameters[0].required == false)
    }

    @Test func screenshotToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = BrowserScreenshotTool(runtime: runtime)
        #expect(tool.definition.id == "browserScreenshot")
        #expect(tool.definition.inputSchema.parameters.isEmpty)
    }

    @Test func javascriptToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = JavaScriptTool(runtime: runtime)
        #expect(tool.definition.id == "browserJavaScript")
        #expect(tool.definition.inputSchema.parameters.count == 1)
        #expect(tool.definition.inputSchema.parameters[0].name == "code")
    }

    @Test func pageInfoToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = PageInfoTool(runtime: runtime)
        #expect(tool.definition.id == "browserPageInfo")
        #expect(tool.definition.inputSchema.parameters.isEmpty)
    }

    @Test func pressKeyToolDefinition() {
        let runtime = BrowserRuntime()
        let tool = PressKeyTool(runtime: runtime)
        #expect(tool.definition.id == "browserPressKey")
        #expect(tool.definition.inputSchema.parameters.count == 1)
        #expect(tool.definition.inputSchema.parameters[0].name == "key")
    }

    @Test func browserToolsReturnErrorWhenChromeNotRunning() async throws {
        let runtime = BrowserRuntime()
        let ctx = ExecutionContext(executionId: "test", conversationId: nil, workspaceId: nil, source: .internal, timeout: nil, createdAt: Date())

        try await ExecutionContext.$current.withValue(ctx) {
            let click = ClickTool(runtime: runtime)
            let clickResult = try await click.run(input: ["selector": "button"])
            #expect(clickResult.contains("Browser is not running"))

            let type = TypeTool(runtime: runtime)
            let typeResult = try await type.run(input: ["selector": "input", "text": "hello"])
            #expect(typeResult.contains("Browser is not running"))

            let extract = ExtractTool(runtime: runtime)
            let extractResult = try await extract.run(input: [:])
            #expect(extractResult.contains("Browser is not running"))

            let js = JavaScriptTool(runtime: runtime)
            let jsResult = try await js.run(input: ["code": "1+1"])
            #expect(jsResult.contains("Browser is not running"))
        }
    }

    @Test func fallbackModeActivatesWhenChromeUnavailable() async {
        let runtime = BrowserRuntime()
        let ctx = ExecutionContext(executionId: "test", conversationId: nil, workspaceId: nil, source: .internal, timeout: nil, createdAt: Date())
        #expect(!runtime.isRunning)
        await runtime.launch(context: ctx)
        #expect(runtime.isFallbackMode)
        #expect(runtime.isRunning)
    }

    @Test func navigateToolWorksInFallbackMode() async throws {
        let runtime = BrowserRuntime()
        let ctx = ExecutionContext(executionId: "test", conversationId: nil, workspaceId: nil, source: .internal, timeout: nil, createdAt: Date())
        await runtime.launch(context: ctx)
        #expect(runtime.isFallbackMode)

        let navTool = NavigateTool(runtime: runtime)
        let result = try await ExecutionContext.$current.withValue(ctx) {
            try await navTool.run(input: ["url": "https://example.com"])
        }
        let lower = result.lowercased()
        #expect(lower.contains("fallback") || lower.contains("fetched"))
    }

    @Test func browserSessionStoreRoundTrip() throws {
        let db = try DatabaseQueue()
        try db.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS browser_sessions (
                    id TEXT PRIMARY KEY,
                    workspaceId TEXT,
                    url TEXT,
                    cookiesJSON TEXT NOT NULL,
                    localStorageJSON TEXT,
                    createdAt REAL NOT NULL,
                    updatedAt REAL NOT NULL
                )
            """)
        }
        let store = BrowserSessionStore(db: db)

        let session1 = BrowserSession(
            id: "test-1",
            workspaceId: "ws-1",
            url: "https://example.com",
            cookiesJSON: "[]",
            localStorageJSON: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        try store.save(session1)

        let loaded = store.session(workspaceId: "ws-1")
        #expect(loaded != nil)
        #expect(loaded?.id == "test-1")
        #expect(loaded?.url == "https://example.com")
        #expect(loaded?.workspaceId == "ws-1")

        let noMatch = store.session(workspaceId: "ws-2")
        #expect(noMatch == nil)
    }
}
