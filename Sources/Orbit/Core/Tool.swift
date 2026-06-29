import Foundation

public struct ToolParameter: Codable, Equatable {
    public let name: String
    public let description: String
    public let type: ParameterType
    public let required: Bool

    public init(name: String, description: String, type: ParameterType, required: Bool) {
        self.name = name
        self.description = description
        self.type = type
        self.required = required
    }
}

public enum ParameterType: String, Codable {
    case string, integer, number, boolean
}

public struct ToolSchema: Codable {
    public let parameters: [ToolParameter]

    public init(parameters: [ToolParameter]) {
        self.parameters = parameters
    }
}

public enum Permission: String, Codable, Sendable {
    case none
    case requiresApproval
}

public struct ToolDefinition: Codable {
    public let id: String
    public let name: String
    public let description: String
    public let inputSchema: ToolSchema
    public var requiredPermission: Permission
    public var supportedPlatforms: [String]?

    public init(id: String, name: String, description: String, inputSchema: ToolSchema, requiredPermission: Permission = .none, supportedPlatforms: [String]? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.requiredPermission = requiredPermission
        self.supportedPlatforms = supportedPlatforms
    }
}

public protocol Tool: AnyObject {
    var definition: ToolDefinition { get }
    func run(input: [String: String]) async throws -> String
}
