import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "goals")

final class GoalStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    func allGoals() -> [PersistedGoal] {
        do {
            return try db.read { database in
                try PersistedGoal.fetchAll(database, sql: "SELECT * FROM goals ORDER BY priority DESC, createdAt DESC")
            }
        } catch {
            log.error("Failed to fetch goals: \(error.localizedDescription)")
            return []
        }
    }

    func goals(status: GoalStatus) -> [PersistedGoal] {
        do {
            return try db.read { database in
                try PersistedGoal.fetchAll(database, sql: "SELECT * FROM goals WHERE status = ? ORDER BY priority DESC, createdAt DESC", arguments: [status.rawValue])
            }
        } catch {
            log.error("Failed to fetch goals by status: \(error.localizedDescription)")
            return []
        }
    }

    func activeGoals() -> [PersistedGoal] {
        goals(status: .active)
    }

    func dueGoals() -> [PersistedGoal] {
        do {
            return try db.read { database in
                try PersistedGoal.fetchAll(database, sql: "SELECT * FROM goals WHERE status = 'active' AND (nextRunAt IS NULL OR nextRunAt <= ?) ORDER BY priority DESC", arguments: [Date().timeIntervalSince1970])
            }
        } catch {
            log.error("Failed to fetch due goals: \(error.localizedDescription)")
            return []
        }
    }

    func goal(id: String) -> PersistedGoal? {
        do {
            return try db.read { database in
                try PersistedGoal.fetchOne(database, sql: "SELECT * FROM goals WHERE id = ?", arguments: [id])
            }
        } catch {
            log.error("Failed to fetch goal: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ goal: PersistedGoal) {
        do {
            var g = goal
            g.updatedAt = Date()
            try db.write { database in
                try g.save(database)
            }
        } catch {
            log.error("Failed to save goal: \(error.localizedDescription)")
        }
    }

    func delete(id: String) {
        do {
            try db.write { database in
                try database.execute(sql: "DELETE FROM goals WHERE id = ?", arguments: [id])
            }
        } catch {
            log.error("Failed to delete goal: \(error.localizedDescription)")
        }
    }

    func updateStatus(id: String, status: GoalStatus) {
        do {
            try db.write { database in
                try database.execute(sql: "UPDATE goals SET status = ?, updatedAt = ? WHERE id = ?", arguments: [status.rawValue, Date().timeIntervalSince1970, id])
            }
        } catch {
            log.error("Failed to update goal status: \(error.localizedDescription)")
        }
    }

    func recordRun(id: String, outcome: String) {
        do {
            let now = Date()
            try db.write { database in
                try database.execute(sql: """
                    UPDATE goals SET lastRunAt = ?, lastOutcome = ?, runCount = runCount + 1, updatedAt = ? WHERE id = ?
                    """, arguments: [now.timeIntervalSince1970, outcome, now.timeIntervalSince1970, id])
            }
        } catch {
            log.error("Failed to record goal run: \(error.localizedDescription)")
        }
    }

    func setNextRun(id: String, nextRunAt: Date?) {
        do {
            try db.write { database in
                try database.execute(sql: "UPDATE goals SET nextRunAt = ?, updatedAt = ? WHERE id = ?", arguments: [nextRunAt?.timeIntervalSince1970, Date().timeIntervalSince1970, id])
            }
        } catch {
            log.error("Failed to set next run: \(error.localizedDescription)")
        }
    }
}

extension PersistedGoal: FetchableRecord {
    init(row: Row) {
        id = row["id"] as? String ?? UUID().uuidString
        description = row["description"] as? String ?? ""
        criteria = row["criteria"] as? String
        status = GoalStatus(rawValue: row["status"] as? String ?? "active") ?? .active
        priority = row["priority"] as? Int ?? 5
        intervalMinutes = row["intervalMinutes"] as? Double
        lastRunAt = (row["lastRunAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        nextRunAt = (row["nextRunAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        lastOutcome = row["lastOutcome"] as? String
        runCount = row["runCount"] as? Int ?? 0
        maxRuns = row["maxRuns"] as? Int
        tags = row["tags"] as? String
        createdAt = Date(timeIntervalSince1970: row["createdAt"] as? Double ?? 0)
        updatedAt = Date(timeIntervalSince1970: row["updatedAt"] as? Double ?? 0)
        conversationId = row["conversationId"] as? String
    }
}

extension PersistedGoal: PersistableRecord {
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["description"] = description
        container["criteria"] = criteria
        container["status"] = status.rawValue
        container["priority"] = priority
        container["intervalMinutes"] = intervalMinutes
        container["lastRunAt"] = lastRunAt?.timeIntervalSince1970
        container["nextRunAt"] = nextRunAt?.timeIntervalSince1970
        container["lastOutcome"] = lastOutcome
        container["runCount"] = runCount
        container["maxRuns"] = maxRuns
        container["tags"] = tags
        container["createdAt"] = createdAt.timeIntervalSince1970
        container["updatedAt"] = updatedAt.timeIntervalSince1970
        container["conversationId"] = conversationId
    }
}
