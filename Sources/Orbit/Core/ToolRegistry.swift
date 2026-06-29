import Foundation

private let blocklistedCommands: Set<String> = [
    "rm -rf /", "dd if=", "mkfs", "format", "> /dev/", ">: /dev/",
    "chmod 777 /", "chown 0:0", "passwd", "sudo ", "doas ",
    ":(){ :|:& };:", "wget http://", "curl http://",
    "python -c 'import os", "import shutil", "eval(", "exec(",
]

public class ToolRegistry {
    private var tools: [String: Tool] = [:]

    public init() {}

    public func register(_ tool: Tool) {
        tools[tool.definition.id] = tool
    }

    public func unregister(id: String) {
        tools.removeValue(forKey: id)
    }

    public func tool(named id: String, filterByPlatform: Bool = false) -> Tool? {
        guard let tool = tools[id] else { return nil }
        if filterByPlatform, !tool.definition.supportsCurrentPlatform {
            return nil
        }
        return tool
    }

    static func isBlocklisted(_ input: String) -> Bool {
        let lower = input.lowercased()
        return blocklistedCommands.contains { lower.contains($0.lowercased()) }
    }

    public var allDefinitions: [ToolDefinition] {
        tools.values.map { $0.definition }
    }

    public var allDefinitionsForCurrentPlatform: [ToolDefinition] {
        tools.values.filter { $0.definition.supportsCurrentPlatform }.map { $0.definition }
    }

    public var allToolNames: [String] {
        tools.keys.sorted()
    }

    public var allToolNamesForCurrentPlatform: [String] {
        tools.values.filter { $0.definition.supportsCurrentPlatform }.map { $0.definition.id }.sorted()
    }
}

extension ToolDefinition {
    var supportsCurrentPlatform: Bool {
        guard let platforms = supportedPlatforms else { return true }
        return platforms.contains(Platform.current.name.lowercased())
    }
}
