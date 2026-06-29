import Foundation

final class PermissionManager {
    private struct AllowEntry {
        let toolName: String
        let grantedAt: Date
    }

    private struct PersistedEntry: Codable {
        let toolName: String
        let grantedAt: Date
    }

    private var allowList: [AllowEntry] = []
    private let sessionTTL: TimeInterval = 300 // 5 minutes
    private let defaultsKey = "com.orbit.permission.allowList"

    init() {
        loadPersisted()
    }

    func requiresApproval(tool: Tool) -> Bool {
        guard tool.definition.requiredPermission == .requiresApproval else { return false }
        clearExpired()
        return !allowList.contains(where: { $0.toolName == tool.definition.name })
    }

    func allowForSession(_ toolName: String) {
        allowList.append(AllowEntry(toolName: toolName, grantedAt: Date()))
        persist()
    }

    func isAllowedForSession(_ toolName: String) -> Bool {
        clearExpired()
        return allowList.contains(where: { $0.toolName == toolName })
    }

    func clearSessionAllowList() {
        allowList.removeAll()
        persist()
    }

    private func loadPersisted() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([PersistedEntry].self, from: data)
        else { return }
        let cutoff = Date().addingTimeInterval(-sessionTTL)
        allowList = entries
            .filter { $0.grantedAt > cutoff }
            .map { AllowEntry(toolName: $0.toolName, grantedAt: $0.grantedAt) }
    }

    private func persist() {
        let entries = allowList.map { PersistedEntry(toolName: $0.toolName, grantedAt: $0.grantedAt) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func clearExpired() {
        let cutoff = Date().addingTimeInterval(-sessionTTL)
        allowList.removeAll { $0.grantedAt < cutoff }
    }
}
