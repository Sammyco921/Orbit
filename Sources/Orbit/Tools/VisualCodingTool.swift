import Foundation

final class VisualCodingTool: Tool {
    var definition = ToolDefinition(
        id: "visualCoding",
        name: "Visual Coding",
        description: "Capture the current screen, analyze the UI design, and generate SwiftUI code that reproduces the visual layout",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "description", description: "Optional additional context about what to build", type: .string, required: false),
            ToolParameter(name: "framework", description: "Target framework: swiftui, uikit, html (default: swiftui)", type: .string, required: false)
        ])
    )

    var screenService: ScreenUnderstandingService?
    var llmService: LLMService?

    func run(input: [String: String]) async throws -> String {
        guard let screenService else {
            return "Screen understanding service not available."
        }
        guard let llmService else {
            return "LLM service not available."
        }

        let userDescription = input["description"] ?? ""
        let framework = input["framework"] ?? "swiftui"

        let snapshot = try await screenService.captureCurrentScreen()
        let screenDescription = screenService.describeScreen(snapshot)

        let prompt = """
        You are a UI-to-code converter. Based on the following screen description, generate \(framework) code that reproduces this UI design.

        \(userDescription.isEmpty ? "" : "Additional context: \(userDescription)\n")

        Screen Description:
        \(screenDescription)

        Generate complete, production-quality \(framework) code that matches this design. Include proper layout, colors, spacing, and styling.
        """

        let messages = [LLMMessage(role: .user, content: prompt)]
        let provider = llmService.currentProvider()
        let code = try await provider.complete(messages: messages)

        return "Generated \(framework) code:\n\n```\(framework)\n\(code)\n```"
    }
}
