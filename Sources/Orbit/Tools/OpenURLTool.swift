import Foundation

final class OpenURLTool: Tool {
    var definition = ToolDefinition(
        id: "openUrl",
        name: "Open URL",
        description: "Open a URL in the default browser",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "url", description: "The URL to open (e.g. https://example.com)", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()

    func run(input: [String: String]) async throws -> String {
        guard let raw = input["url"], !raw.isEmpty else {
            return "No URL provided."
        }
        guard raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") else {
            throw OrbitError.securityBlocked("Only http and https URLs are allowed")
        }
        if Platform.current == .linux {
            try await LinuxCommands.openURL(raw)
            return "Opened \(raw)"
        }
        let result = try await scriptExecutor.run(executable: "/usr/bin/open", arguments: [raw])
        return result.isEmpty ? "Opened \(raw)" : result
    }
}
