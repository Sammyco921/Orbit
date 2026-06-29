import Foundation

// MARK: - SummarizeTool

final class SummarizeTool: Tool {
    var definition = ToolDefinition(
        id: "summarize",
        name: "Summarize",
        description: "Summarize a given text",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "The text to summarize", type: .string, required: true),
            ToolParameter(name: "maxLength", description: "Maximum length of the summary in words (default: 100)", type: .integer, required: false),
        ])
    )

    weak var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"] else {
            return "Missing required parameter: text"
        }
        let maxLength = Int(input["maxLength"] ?? "100") ?? 100
        guard let llm = llmService?.currentProvider() else {
            return "LLM not available"
        }
        let prompt = """
            Summarize the following text in \(maxLength) words or fewer. \
            Be concise and capture only the key points.

            \(text)
            """
        return try await llm.complete(messages: [LLMMessage(role: .user, content: prompt)])
    }
}

// MARK: - ExplainTool

final class ExplainTool: Tool {
    var definition = ToolDefinition(
        id: "explain",
        name: "Explain",
        description: "Explain a concept, code snippet, or text",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "The text, code, or concept to explain", type: .string, required: true),
            ToolParameter(name: "style", description: "Explanation style: simple, detailed, or analogy (default: simple)", type: .string, required: false),
        ])
    )

    weak var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"] else {
            return "Missing required parameter: text"
        }
        let style = input["style"] ?? "simple"
        let styleGuide: String
        switch style {
        case "detailed": styleGuide = "Provide a thorough, in-depth explanation."
        case "analogy": styleGuide = "Use an analogy or metaphor to explain it simply."
        default: styleGuide = "Explain in simple, beginner-friendly terms."
        }
        guard let llm = llmService?.currentProvider() else {
            return "LLM not available"
        }
        let prompt = """
            \(styleGuide)

            \(text)
            """
        return try await llm.complete(messages: [LLMMessage(role: .user, content: prompt)])
    }
}

// MARK: - TranslateTool

final class TranslateTool: Tool {
    var definition = ToolDefinition(
        id: "translate",
        name: "Translate",
        description: "Translate text to a target language",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "text", description: "The text to translate", type: .string, required: true),
            ToolParameter(name: "targetLanguage", description: "The target language (e.g. Spanish, French, Japanese)", type: .string, required: true),
        ])
    )

    weak var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let text = input["text"] else {
            return "Missing required parameter: text"
        }
        guard let target = input["targetLanguage"] else {
            return "Missing required parameter: targetLanguage"
        }
        guard let llm = llmService?.currentProvider() else {
            return "LLM not available"
        }
        let prompt = """
            Translate the following text to \(target). Return only the translation, no explanations.

            \(text)
            """
        return try await llm.complete(messages: [LLMMessage(role: .user, content: prompt)])
    }
}

// MARK: - RefactorTool

final class RefactorTool: Tool {
    var definition = ToolDefinition(
        id: "refactor",
        name: "Refactor",
        description: "Refactor code according to given instructions",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "code", description: "The code to refactor", type: .string, required: true),
            ToolParameter(name: "language", description: "The programming language of the code (e.g. Swift, Python)", type: .string, required: true),
            ToolParameter(name: "instructions", description: "What to refactor (e.g. 'convert to async/await', 'extract into functions')", type: .string, required: true),
        ])
    )

    weak var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let code = input["code"] else {
            return "Missing required parameter: code"
        }
        guard let lang = input["language"] else {
            return "Missing required parameter: language"
        }
        guard let instructions = input["instructions"] else {
            return "Missing required parameter: instructions"
        }
        guard let llm = llmService?.currentProvider() else {
            return "LLM not available"
        }
        let prompt = """
            Refactor the following \(lang) code according to these instructions: \(instructions)

            Return only the refactored code, with a brief explanation of changes.

            ```\(lang)
            \(code)
            ```
            """
        return try await llm.complete(messages: [LLMMessage(role: .user, content: prompt)])
    }
}
