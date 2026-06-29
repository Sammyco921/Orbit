import Foundation

// MARK: - Navigate Tool

final class NavigateTool: Tool {
    var definition = ToolDefinition(
        id: "browserNavigate",
        name: "Navigate Browser",
        description: "Navigate Chrome to a URL and wait for the page to load",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "url", description: "The URL to navigate to (e.g. https://example.com)", type: .string, required: true)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let url = input["url"], !url.isEmpty else {
            return "No URL provided."
        }
        guard url.lowercased().hasPrefix("http://") || url.lowercased().hasPrefix("https://") else {
            return "Only http and https URLs are supported."
        }
        if !runtime.isRunning {
            await runtime.launch(context: ctx)
        }
        return try await runtime.navigate(url: url, context: ctx)
    }
}

// MARK: - Click Tool

final class ClickTool: Tool {
    var definition = ToolDefinition(
        id: "browserClick",
        name: "Click Element",
        description: "Click an element on the current page identified by a CSS selector",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "selector", description: "CSS selector for the element to click (e.g. 'button.submit', '#login-link', 'a[href=\"/signup\"]')", type: .string, required: true)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let selector = input["selector"], !selector.isEmpty else {
            return "No selector provided."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "Click is not available in fallback mode (Chrome not running)."
        }
        return try await runtime.click(selector: selector, context: ctx)
    }
}

// MARK: - Type Text Tool

final class TypeTool: Tool {
    var definition = ToolDefinition(
        id: "browserType",
        name: "Type Text",
        description: "Type text into an input field on the current page identified by a CSS selector",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "selector", description: "CSS selector for the input field", type: .string, required: true),
            ToolParameter(name: "text", description: "The text to type", type: .string, required: true)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let selector = input["selector"], !selector.isEmpty else {
            return "No selector provided."
        }
        guard let text = input["text"] else {
            return "No text provided."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "Type is not available in fallback mode (Chrome not running)."
        }
        return try await runtime.type(selector: selector, text: text, context: ctx)
    }
}

// MARK: - Extract Text Tool

final class ExtractTool: Tool {
    var definition = ToolDefinition(
        id: "browserExtract",
        name: "Extract Page Text",
        description: "Extract text content from the current page or a specific element using a CSS selector",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "selector", description: "Optional CSS selector. If omitted, extracts all visible text from the page", type: .string, required: false)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        let selector = input["selector"]
        let maxLength = 10000
        let text = try await runtime.extractText(selector: selector, context: ctx)
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "\n\n[Output truncated at \(maxLength) characters]"
        }
        return text
    }
}

// MARK: - Browser Screenshot Tool

final class BrowserScreenshotTool: Tool {
    var definition = ToolDefinition(
        id: "browserScreenshot",
        name: "Browser Screenshot",
        description: "Take a screenshot of the current browser page. Returns the screenshot as a base64-encoded image.",
        inputSchema: ToolSchema(parameters: [])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "Screenshot is not available in fallback mode (Chrome not running)."
        }
        let data = try await runtime.takeScreenshot(context: ctx)
        return data.base64EncodedString()
    }
}

// MARK: - Evaluate JavaScript Tool

final class JavaScriptTool: Tool {
    var definition = ToolDefinition(
        id: "browserJavaScript",
        name: "Run JavaScript",
        description: "Execute arbitrary JavaScript in the current browser page and return the result",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "code", description: "JavaScript code to execute", type: .string, required: true)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let code = input["code"], !code.isEmpty else {
            return "No JavaScript code provided."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "JavaScript evaluation is not available in fallback mode (Chrome not running)."
        }
        return try await runtime.evaluateJavaScript(code, context: ctx)
    }
}

// MARK: - Get Page Info Tool

final class PageInfoTool: Tool {
    var definition = ToolDefinition(
        id: "browserPageInfo",
        name: "Page Info",
        description: "Get the current page URL and title from the browser",
        inputSchema: ToolSchema(parameters: [])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "Running in fallback mode (Chrome not available). Page info is limited."
        }
        let url = try await runtime.getCurrentURL(context: ctx)
        let title = try await runtime.getTitle(context: ctx)
        return "Title: \(title)\nURL: \(url)"
    }
}

// MARK: - Press Key Tool

final class PressKeyTool: Tool {
    var definition = ToolDefinition(
        id: "browserPressKey",
        name: "Press Key",
        description: "Press a keyboard key in the browser. Supported keys: Enter, Tab, Escape, Backspace, Delete, Arrow keys.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "key", description: "The key to press (e.g. Enter, Tab, Escape, ArrowDown, ArrowUp)", type: .string, required: true)
        ])
    )

    let runtime: BrowserRuntime

    init(runtime: BrowserRuntime) {
        self.runtime = runtime
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let key = input["key"], !key.isEmpty else {
            return "No key provided."
        }
        guard runtime.isRunning else {
            return "Browser is not running. Use browserNavigate first."
        }
        if runtime.isFallbackMode {
            return "Press key is not available in fallback mode (Chrome not running)."
        }
        return try await runtime.pressKey(key, context: ctx)
    }
}
