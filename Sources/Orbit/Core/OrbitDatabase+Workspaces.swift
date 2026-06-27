import Foundation
import GRDB

// MARK: - Workspace CRUD

extension OrbitDatabase {
    func loadAllWorkspaces() throws -> [Workspace] {
        try db.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM workspaces ORDER BY name ASC")
            return try rows.map { row in
                guard let idStr: String = row["id"], let id = UUID(uuidString: idStr) else {
                    throw OrbitError.databaseCorruption("Missing or invalid workspace id")
                }
                guard let name: String = row["name"] else {
                    throw OrbitError.databaseCorruption("Missing name for workspace \(idStr)")
                }
                guard let icon: String = row["icon"] else {
                    throw OrbitError.databaseCorruption("Missing icon for workspace \(idStr)")
                }
                guard let createdAtInterval: TimeInterval = row["createdAt"] else {
                    throw OrbitError.databaseCorruption("Missing createdAt for workspace \(idStr)")
                }
                guard let updatedAtInterval: TimeInterval = row["updatedAt"] else {
                    throw OrbitError.databaseCorruption("Missing updatedAt for workspace \(idStr)")
                }
                let kbIds: [String] = decodeJSON(row["knowledgeBaseIdsJSON"] as? String) ?? []
                return Workspace(
                    id: id,
                    name: name,
                    icon: icon,
                    path: row["path"] as? String,
                    knowledgeBaseIds: kbIds,
                    createdAt: Date(timeIntervalSince1970: createdAtInterval),
                    updatedAt: Date(timeIntervalSince1970: updatedAtInterval)
                )
            }
        }
    }

    func saveWorkspace(_ workspace: Workspace) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO workspaces (id, name, icon, path, knowledgeBaseIdsJSON, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                workspace.id.uuidString,
                workspace.name,
                workspace.icon,
                workspace.path,
                encodeJSON(workspace.knowledgeBaseIds),
                workspace.createdAt.timeIntervalSince1970,
                workspace.updatedAt.timeIntervalSince1970
            ])
        }
    }

    func deleteWorkspace(_ id: UUID) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE conversations SET workspaceId = NULL WHERE workspaceId = ?", arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM workspaces WHERE id = ?", arguments: [id.uuidString])
        }
    }
}
