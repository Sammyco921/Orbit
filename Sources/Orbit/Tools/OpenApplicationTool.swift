import Foundation

final class OpenApplicationTool: Tool {
    var definition = ToolDefinition(
        id: "openApp",
        name: "Open Application",
        description: "Open a macOS application by name",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "name", description: "Name of the application to open (e.g. Safari, Chrome, Terminal, Finder)", type: .string, required: true)
        ])
    )

    private let scriptExecutor = ScriptExecutor()
    private let knownApps = ["Safari", "Chrome", "Finder", "Mail", "Calendar", "Notes",
                             "Messages", "Spotify", "Terminal", "System Settings",
                             "Photos", "Music", "Podcasts", "FaceTime", "Maps",
                             "Calculator", "Reminders", "Books", "News", "Weather",
                             "Contacts", "Preview", "TextEdit", "Stickies",
                             "Keynote", "Pages", "Numbers", "Xcode", "Slack",
                             "Discord", "Notion", "Obsidian", "Figma", "iTerm",
                             "Activity Monitor", "Console", "Dictionary"]

    func run(input: [String: String]) async throws -> String {
        let rawName = input["name"] ?? ""
        guard !rawName.isEmpty else {
            return "Which app? Available: Safari, Chrome, Terminal, Finder, and more."
        }

        if Platform.current == .linux {
            try await LinuxCommands.openApplication(rawName)
            return "Opened \(rawName)"
        }

        if let exact = knownApps.first(where: { $0.lowercased() == rawName.lowercased() }) {
            return try await launch(exact)
        }

        if let partial = knownApps.first(where: { $0.lowercased().contains(rawName.lowercased()) }) {
            return try await launch(partial)
        }

        return try await launch(rawName)
    }

    private func launch(_ name: String) async throws -> String {
        let result = try await scriptExecutor.run(executable: "/usr/bin/open", arguments: ["-a", name])
        return result.isEmpty ? "Opened \(name)" : result
    }
}
