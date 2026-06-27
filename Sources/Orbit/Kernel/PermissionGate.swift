import Foundation

final class PermissionGate {
    private let permissionManager: PermissionManager

    init(permissionManager: PermissionManager) {
        self.permissionManager = permissionManager
    }

    func check(intent: ExecutionIntent, tool: Tool) async throws {
        guard tool.definition.requiredPermission == .requiresApproval else { return }

        switch intent.approvalMode {
        case .interactive:
            let response = await PendingApproval.shared.requestApproval(
                toolName: tool.definition.name,
                input: intent.input
            )
            switch response {
            case .deny:
                throw OrbitError.toolRequiresApproval(tool.definition.name)
            case .allow, .allowOnce:
                break
            case .allowForSession:
                permissionManager.allowForSession(tool.definition.name)
            }
        case .autoApprove:
            break
        case .throwOnApproval:
            throw OrbitError.toolRequiresApproval(tool.definition.name)
        }
    }
}
