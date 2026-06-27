import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "workspace")

/// Manages workspace CRUD, active workspace tracking, and UserDefaults persistence.
final class WorkspaceService {
    private(set) var workspaces: [Workspace] = []
    private(set) var activeWorkspaceId: UUID? {
        didSet {
            if let id = activeWorkspaceId {
                UserDefaults.standard.set(id.uuidString, forKey: "activeWorkspaceId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeWorkspaceId")
            }
        }
    }

    private weak var database: OrbitDatabase?

    func configure(database: OrbitDatabase) {
        self.database = database
        loadWorkspaces()
    }

    func loadWorkspaces() {
        guard let db = database else {
            workspaces = []
            activeWorkspaceId = nil
            return
        }
        do {
            workspaces = try db.loadAllWorkspaces()
            if workspaces.isEmpty {
                let defaultWS = Workspace(name: "Default", icon: "folder")
                try db.saveWorkspace(defaultWS)
                workspaces = [defaultWS]
            }
            // Restore active workspace from UserDefaults, fall back to first
            if let savedId = UserDefaults.standard.string(forKey: "activeWorkspaceId"),
               let uuid = UUID(uuidString: savedId),
               workspaces.contains(where: { $0.id == uuid }) {
                activeWorkspaceId = uuid
            } else {
                activeWorkspaceId = workspaces.first?.id
            }
            log.debug("Loaded \(self.workspaces.count) workspaces")
        } catch {
            log.error("Failed to load workspaces: \(error.localizedDescription)")
            workspaces = []
            activeWorkspaceId = nil
        }
    }

    func createWorkspace(name: String, icon: String = "folder", path: String? = nil) -> Workspace {
        let ws = Workspace(name: name, icon: icon, path: path)
        workspaces.append(ws)
        activeWorkspaceId = ws.id
        saveWorkspaces()
        return ws
    }

    func updateWorkspace(_ id: UUID, name: String? = nil, icon: String? = nil, path: String? = nil) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        if let name = name { workspaces[index].name = name }
        if let icon = icon { workspaces[index].icon = icon }
        if let path = path { workspaces[index].path = path }
        workspaces[index].updatedAt = Date()
        saveWorkspaces()
    }

    func deleteWorkspace(_ id: UUID) {
        workspaces.removeAll { $0.id == id }
        if activeWorkspaceId == id {
            activeWorkspaceId = workspaces.first?.id
        }
        guard let db = database else { return }
        try? db.deleteWorkspace(id)
    }

    func selectWorkspace(_ id: UUID) {
        activeWorkspaceId = id
    }

    var activeWorkspace: Workspace? {
        activeWorkspaceId.flatMap { id in workspaces.first(where: { $0.id == id }) }
    }

    private func saveWorkspaces() {
        guard let db = database else { return }
        for ws in workspaces {
            try? db.saveWorkspace(ws)
        }
    }
}
