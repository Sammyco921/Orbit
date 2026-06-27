import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "audit")

final class AuditService {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    func record(_ entry: ExecutionLogEntry) {
        do {
            try db.write { database in
                try database.execute(sql: """
                    INSERT INTO execution_log (id, sessionId, toolName, inputJSON, outputJSON, outcome, errorDetail, approvalId, conversationId, durationMs, createdAt, userContext)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                    entry.id,
                    entry.sessionId,
                    entry.toolName,
                    entry.inputJSON,
                    entry.outputJSON,
                    entry.outcome,
                    entry.errorDetail,
                    entry.approvalId,
                    entry.conversationId,
                    entry.durationMs,
                    entry.createdAt.timeIntervalSince1970,
                    entry.userContext,
                ])
            }
        } catch {
            log.error("Failed to record execution log: \(error.localizedDescription)")
        }
    }

    func executions(sessionId: String) -> [ExecutionLogEntry] {
        query(sql: "SELECT * FROM execution_log WHERE sessionId = ? ORDER BY createdAt ASC", arguments: [sessionId])
    }

    func executions(toolName: String, since: Date) -> [ExecutionLogEntry] {
        query(sql: "SELECT * FROM execution_log WHERE toolName = ? AND createdAt >= ? ORDER BY createdAt DESC", arguments: [toolName, since.timeIntervalSince1970])
    }

    func executions(conversationId: String) -> [ExecutionLogEntry] {
        query(sql: "SELECT * FROM execution_log WHERE conversationId = ? ORDER BY createdAt DESC", arguments: [conversationId])
    }

    func recent(limit: Int = 50) -> [ExecutionLogEntry] {
        query(sql: "SELECT * FROM execution_log ORDER BY createdAt DESC LIMIT ?", arguments: [limit])
    }

    func sessions(limit: Int = 20) -> [(sessionId: String, toolName: String, createdAt: Date, outcome: String)] {
        do {
            return try db.read { database in
                let rows = try Row.fetchAll(database, sql: """
                    SELECT sessionId, toolName, outcome, createdAt FROM execution_log
                    WHERE sessionId IN (SELECT DISTINCT sessionId FROM execution_log ORDER BY createdAt DESC)
                    ORDER BY createdAt DESC LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    (
                        sessionId: row["sessionId"] as? String ?? "",
                        toolName: row["toolName"] as? String ?? "",
                        createdAt: Date(timeIntervalSince1970: row["createdAt"] as? Double ?? 0),
                        outcome: row["outcome"] as? String ?? ""
                    )
                }
            }
        } catch {
            log.error("Failed to query sessions: \(error.localizedDescription)")
            return []
        }
    }

    func sessionsList(limit: Int = 20) -> [(sessionId: String, count: Int, firstTool: String, lastTime: Date)] {
        do {
            return try db.read { database in
                let rows = try Row.fetchAll(database, sql: """
                    SELECT sessionId, COUNT(*) as count,
                           (SELECT toolName FROM execution_log e2 WHERE e2.sessionId = e1.sessionId ORDER BY createdAt ASC LIMIT 1) as firstTool,
                           MAX(createdAt) as lastTime
                    FROM execution_log e1
                    GROUP BY sessionId
                    ORDER BY lastTime DESC
                    LIMIT ?
                    """, arguments: [limit])
                return rows.map { row in
                    (
                        sessionId: row["sessionId"] as? String ?? "",
                        count: Int(row["count"] as? Int64 ?? 0),
                        firstTool: row["firstTool"] as? String ?? "",
                        lastTime: Date(timeIntervalSince1970: row["lastTime"] as? Double ?? 0)
                    )
                }
            }
        } catch {
            log.error("Failed to query sessions list: \(error.localizedDescription)")
            return []
        }
    }

    func exportJSON(sessionId: String) -> Data? {
        let entries = executions(sessionId: sessionId)
        return try? JSONEncoder().encode(entries)
    }

    func toolUsageStats(limit: Int = 5) -> [(toolName: String, count: Int, successRate: Float)] {
        do {
            return try db.read { database in
                let rows = try Row.fetchAll(database, sql: """
                    SELECT toolName, COUNT(*) AS cnt,
                           CAST(SUM(CASE WHEN outcome = 'succeeded' OR outcome = 'success' THEN 1 ELSE 0 END) AS REAL) / COUNT(*) AS successRate
                    FROM execution_log
                    GROUP BY toolName
                    ORDER BY cnt DESC
                    LIMIT ?
                """, arguments: [limit])
                return rows.map { row in
                    let toolName: String = row["toolName"]
                    let cnt: Int64 = row["cnt"]
                    let sr: Double = row["successRate"]
                    return (toolName, Int(cnt), Float(sr))
                }
            }
        } catch {
            log.error("Failed to query tool usage stats: \(error.localizedDescription)")
            return []
        }
    }

    func exportCSV(sessionId: String) -> String {
        let entries = executions(sessionId: sessionId)
        var csv = "id,sessionId,toolName,outcome,errorDetail,durationMs,createdAt\n"
        for entry in entries {
            let escaped = entry.toolName.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(entry.id),\(entry.sessionId),\"\(escaped)\",\(entry.outcome),\(entry.errorDetail ?? ""),\(entry.durationMs),\(entry.createdAt.timeIntervalSince1970)\n"
        }
        return csv
    }

    private func query(sql: String, arguments: StatementArguments) -> [ExecutionLogEntry] {
        do {
            return try db.read { database in
                try ExecutionLogEntry.fetchAll(database, sql: sql, arguments: arguments)
            }
        } catch {
            log.error("Audit query failed: \(error.localizedDescription)")
            return []
        }
    }
}

extension ExecutionLogEntry: FetchableRecord {
    init(row: Row) {
        id = row["id"] as? String ?? UUID().uuidString
        sessionId = row["sessionId"] as? String ?? ""
        toolName = row["toolName"] as? String ?? ""
        inputJSON = row["inputJSON"] as? String
        outputJSON = row["outputJSON"] as? String
        outcome = row["outcome"] as? String ?? "unknown"
        errorDetail = row["errorDetail"] as? String
        approvalId = row["approvalId"] as? String
        conversationId = row["conversationId"] as? String
        durationMs = row["durationMs"] as? Double ?? 0
        createdAt = Date(timeIntervalSince1970: row["createdAt"] as? Double ?? 0)
        userContext = row["userContext"] as? String
    }
}
