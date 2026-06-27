import Foundation

final class PermissionManager {
    private struct AllowEntry {
        let toolName: String
        let grantedAt: Date
    }

    private var allowList: [AllowEntry] = []
    private let sessionTTL: TimeInterval = 300 // 5 minutes

    func requiresApproval(tool: Tool) -> Bool {
        guard tool.definition.requiredPermission == .requiresApproval else { return false }
        clearExpired()
        return !allowList.contains(where: { $0.toolName == tool.definition.name })
    }

    func allowForSession(_ toolName: String) {
        allowList.append(AllowEntry(toolName: toolName, grantedAt: Date()))
    }

    func isAllowedForSession(_ toolName: String) -> Bool {
        clearExpired()
        return allowList.contains(where: { $0.toolName == toolName })
    }

    func clearSessionAllowList() {
        allowList.removeAll()
    }

    private func clearExpired() {
        let cutoff = Date().addingTimeInterval(-sessionTTL)
        allowList.removeAll { $0.grantedAt < cutoff }
    }
}
