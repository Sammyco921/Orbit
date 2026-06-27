import Foundation

enum AgentEvent: Sendable {
    case thought(String)
    case toolExecution(toolName: String, input: [String: String])
    case toolResult(toolName: String, output: String)
    case error(String)
    case completed(String)
}
