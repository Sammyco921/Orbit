import Foundation

final class KillAppTool: Tool {
    var definition = ToolDefinition(
        id: "killApp",
        name: "Quit Application",
        description: "Force quit a running application by name",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "name", description: "Name of the application to quit (e.g. Safari, Chrome)", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let name = input["name"], !name.isEmpty else {
            return "Which app to quit?"
        }
        let safeName = name.trimmingCharacters(in: .whitespaces)
        guard !safeName.isEmpty, safeName.range(of: "^[a-zA-Z0-9 ._-]+$", options: .regularExpression) != nil else {
            throw OrbitError.securityBlocked("Invalid application name: '\(name)'")
        }
        let result = try await scriptExecutor.run(executable: "/usr/bin/pkill", arguments: ["-i", safeName])
        return result.isEmpty ? "Quit \(safeName)" : result
    }
}
