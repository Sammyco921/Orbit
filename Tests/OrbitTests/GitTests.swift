import Testing
import Foundation
@testable import Orbit

@Test func gitToolsAreRegistered() {
    let registry = ToolRegistry()
    registry.register(GitStatusTool())
    registry.register(GitDiffTool())
    registry.register(GitLogTool())
    registry.register(GitCommitTool())
    registry.register(GitBranchTool())
    registry.register(GitPushTool())
    registry.register(GitPullTool())
    registry.register(GitStashTool())
    registry.register(GitInitTool())
    registry.register(GitCloneTool())

    #expect(registry.tool(named: "gitStatus") != nil)
    #expect(registry.tool(named: "gitDiff") != nil)
    #expect(registry.tool(named: "gitLog") != nil)
    #expect(registry.tool(named: "gitCommit") != nil)
    #expect(registry.tool(named: "gitBranch") != nil)
    #expect(registry.tool(named: "gitPush") != nil)
    #expect(registry.tool(named: "gitPull") != nil)
    #expect(registry.tool(named: "gitStash") != nil)
    #expect(registry.tool(named: "gitInit") != nil)
    #expect(registry.tool(named: "gitClone") != nil)
}

@Test func gitReadOnlyToolsDefaultToNonePermission() {
    #expect(GitStatusTool().definition.requiredPermission == .none)
    #expect(GitDiffTool().definition.requiredPermission == .none)
    #expect(GitLogTool().definition.requiredPermission == .none)
}

@Test func gitModifyingToolsDefaultToNonePermissionInDefinition() {
    #expect(GitCommitTool().definition.requiredPermission == .none)
    #expect(GitBranchTool().definition.requiredPermission == .none)
    #expect(GitPushTool().definition.requiredPermission == .none)
    #expect(GitPullTool().definition.requiredPermission == .none)
    #expect(GitStashTool().definition.requiredPermission == .none)
    #expect(GitInitTool().definition.requiredPermission == .none)
    #expect(GitCloneTool().definition.requiredPermission == .none)
}

@Test func gitToolsRegisteredWithCorrectPermissions() {
    let service = ToolService(eventBus: EventBus(), screenUnderstandingService: ScreenUnderstandingService())
    let reg = service.toolRegistry

    func check(_ name: String, expected: Permission) {
        guard let tool = reg.tool(named: name) else {
            Issue.record("Tool \(name) not found")
            return
        }
        #expect(tool.definition.requiredPermission == expected)
    }

    check("gitStatus", expected: .none)
    check("gitDiff", expected: .none)
    check("gitLog", expected: .none)
    check("gitCommit", expected: .requiresApproval)
    check("gitBranch", expected: .requiresApproval)
    check("gitPush", expected: .requiresApproval)
    check("gitPull", expected: .requiresApproval)
    check("gitStash", expected: .requiresApproval)
    check("gitInit", expected: .requiresApproval)
    check("gitClone", expected: .requiresApproval)
}

@Test func gitStatusToolHasRequiredParameters() {
    let tool = GitStatusTool()
    let params = tool.definition.inputSchema.parameters
    #expect(params.count == 1)
    #expect(params[0].name == "path")
    #expect(params[0].required == false)
}

@Test func gitCommitToolRequiresMessage() {
    let tool = GitCommitTool()
    let msg = tool.definition.inputSchema.parameters.first { $0.name == "message" }
    #expect(msg != nil)
    #expect(msg?.required == true)
}

@Test func gitBranchToolDefaultsToListAction() {
    let tool = GitBranchTool()
    let action = tool.definition.inputSchema.parameters.first { $0.name == "action" }
    #expect(action != nil)
    #expect(action?.required == false)
}

@Test func gitInitToolRequiresPath() {
    let tool = GitInitTool()
    let path = tool.definition.inputSchema.parameters.first { $0.name == "path" }
    #expect(path != nil)
    #expect(path?.required == true)
}

@Test func gitCloneToolRequiresUrl() {
    let tool = GitCloneTool()
    let url = tool.definition.inputSchema.parameters.first { $0.name == "url" }
    #expect(url != nil)
    #expect(url?.required == true)
}
