import Foundation
import GRDB

struct BrowserSession: Codable {
    let id: String
    let workspaceId: String?
    let url: String?
    let cookiesJSON: String
    let localStorageJSON: String?
    let createdAt: Date
    let updatedAt: Date
}

final class BrowserSessionStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) { self.db = db }

    func save(_ session: BrowserSession) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO browser_sessions (id, workspaceId, url, cookiesJSON, localStorageJSON, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                session.id, session.workspaceId, session.url,
                session.cookiesJSON, session.localStorageJSON,
                session.createdAt.timeIntervalSince1970,
                session.updatedAt.timeIntervalSince1970
            ])
        }
    }

    func session(workspaceId: String?) -> BrowserSession? {
        try? db.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT * FROM browser_sessions WHERE workspaceId IS ? ORDER BY updatedAt DESC LIMIT 1
            """, arguments: [workspaceId])
            guard let row else { return nil }
            return BrowserSession(
                id: row["id"],
                workspaceId: row["workspaceId"],
                url: row["url"],
                cookiesJSON: row["cookiesJSON"],
                localStorageJSON: row["localStorageJSON"],
                createdAt: Date(timeIntervalSince1970: row["createdAt"]),
                updatedAt: Date(timeIntervalSince1970: row["updatedAt"])
            )
        }
    }

    func deleteSession(workspaceId: String?) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM browser_sessions WHERE workspaceId IS ?", arguments: [workspaceId])
        }
    }
}
