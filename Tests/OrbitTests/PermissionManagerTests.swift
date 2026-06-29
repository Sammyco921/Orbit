import Testing
import Foundation
@testable import Orbit

struct PermissionManagerTests {

    init() {
        UserDefaults.standard.removeObject(forKey: "com.orbit.permission.allowList")
    }

    @Test func defaultPermissionFromToolDefinition() {
        let manager = PermissionManager()
        let tool = MockTool(definition: ToolDefinition(
            id: "safe_tool",
            name: "Safe",
            description: "A safe tool",
            inputSchema: ToolSchema(parameters: []),
            requiredPermission: .none
        ))
        #expect(manager.requiresApproval(tool: tool) == false)
    }

    @Test func requiresApprovalFromDefinition() {
        let manager = PermissionManager()
        let tool = MockTool(definition: ToolDefinition(
            id: "sensitive_tool",
            name: "Sensitive",
            description: "Requires approval",
            inputSchema: ToolSchema(parameters: []),
            requiredPermission: .requiresApproval
        ))
        #expect(manager.requiresApproval(tool: tool) == true)
    }

    @Test func allowForSessionBypassesApproval() {
        let manager = PermissionManager()
        let tool = MockTool(definition: ToolDefinition(
            id: "sensitive_tool",
            name: "Sensitive",
            description: "Requires approval",
            inputSchema: ToolSchema(parameters: []),
            requiredPermission: .requiresApproval
        ))
        manager.allowForSession("Sensitive")
        #expect(manager.requiresApproval(tool: tool) == false)
    }

    @Test func isAllowedForSession() {
        let manager = PermissionManager()
        #expect(manager.isAllowedForSession("Test") == false)
        manager.allowForSession("Test")
        #expect(manager.isAllowedForSession("Test") == true)
    }

    @Test func clearSessionAllowList() {
        let manager = PermissionManager()
        manager.allowForSession("Test")
        #expect(manager.isAllowedForSession("Test") == true)
        manager.clearSessionAllowList()
        #expect(manager.isAllowedForSession("Test") == false)
    }
}

// MARK: - Helpers

private final class MockTool: Tool {
    let definition: ToolDefinition
    init(definition: ToolDefinition) { self.definition = definition }
    func run(input: [String: String]) async throws -> String { "mock" }
}
