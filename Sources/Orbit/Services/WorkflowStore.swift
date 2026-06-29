import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "workflows")

final class WorkflowStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    // MARK: - Definitions

    func allDefinitions() -> [WorkflowDefinition] {
        do {
            return try db.read { database in
                try Row.fetchAll(database, sql: "SELECT * FROM workflow_definitions ORDER BY updatedAt DESC").map(WorkflowDefinition.init(row:))
            }
        } catch {
            log.error("Failed to fetch workflows: \(error.localizedDescription)")
            return []
        }
    }

    func definition(id: String) -> WorkflowDefinition? {
        do {
            return try db.read { database in
                guard let row = try Row.fetchOne(database, sql: "SELECT * FROM workflow_definitions WHERE id = ?", arguments: [id]) else { return nil }
                return WorkflowDefinition(row: row)
            }
        } catch {
            log.error("Failed to fetch workflow: \(error.localizedDescription)")
            return nil
        }
    }

    func saveDefinition(_ workflow: WorkflowDefinition) {
        do {
            let stepsJSON = WorkflowDefinition.encodeSteps(workflow.steps)
            let variablesJSON = WorkflowDefinition.encodeVariables(workflow.variables)
            let triggersJSON = WorkflowDefinition.encodeTriggers(workflow.triggers)
            try db.write { database in
                try database.execute(sql: """
                    INSERT OR REPLACE INTO workflow_definitions (id, name, description, stepsJSON, variablesJSON, triggersJSON, tags, nextRunAt, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                    workflow.id,
                    workflow.name,
                    workflow.description,
                    stepsJSON,
                    variablesJSON,
                    triggersJSON,
                    workflow.tags,
                    workflow.nextRunAt?.timeIntervalSince1970,
                    workflow.createdAt.timeIntervalSince1970,
                    Date().timeIntervalSince1970,
                ])
            }
        } catch {
            log.error("Failed to save workflow: \(error.localizedDescription)")
        }
    }

    func deleteDefinition(id: String) {
        do {
            try db.write { database in
                try database.execute(sql: "DELETE FROM workflow_definitions WHERE id = ?", arguments: [id])
                try database.execute(sql: "DELETE FROM workflow_executions WHERE workflowId = ?", arguments: [id])
            }
        } catch {
            log.error("Failed to delete workflow: \(error.localizedDescription)")
        }
    }

    func dueScheduledDefinitions() -> [WorkflowDefinition] {
        do {
            return try db.read { database in
                try Row.fetchAll(database, sql: """
                    SELECT * FROM workflow_definitions
                    WHERE triggersJSON LIKE '%"scheduled"%'
                      AND (nextRunAt IS NULL OR nextRunAt <= ?)
                    ORDER BY updatedAt ASC
                """, arguments: [Date().timeIntervalSince1970]).map(WorkflowDefinition.init(row:))
            }
        } catch {
            log.error("Failed to fetch due workflows: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Executions

    func executions(workflowId: String) -> [WorkflowExecution] {
        do {
            return try db.read { database in
                try Row.fetchAll(database, sql: "SELECT * FROM workflow_executions WHERE workflowId = ? ORDER BY startedAt DESC", arguments: [workflowId]).map(WorkflowExecution.init(row:))
            }
        } catch {
            log.error("Failed to fetch executions: \(error.localizedDescription)")
            return []
        }
    }

    func execution(id: String) -> WorkflowExecution? {
        do {
            return try db.read { database in
                guard let row = try Row.fetchOne(database, sql: "SELECT * FROM workflow_executions WHERE id = ?", arguments: [id]) else { return nil }
                return WorkflowExecution(row: row)
            }
        } catch {
            log.error("Failed to fetch execution: \(error.localizedDescription)")
            return nil
        }
    }

    func saveExecution(_ execution: WorkflowExecution) {
        do {
            let stepResultsJSON = WorkflowExecution.encodeStepResults(execution.stepResults)
            let variablesJSON = WorkflowExecution.encodeVariables(execution.variables)
            try db.write { database in
                try database.execute(sql: """
                    INSERT OR REPLACE INTO workflow_executions (id, workflowId, status, startedAt, completedAt, stepResultsJSON, variablesJSON, error)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                    execution.id,
                    execution.workflowId,
                    execution.status.rawValue,
                    execution.startedAt.timeIntervalSince1970,
                    execution.completedAt?.timeIntervalSince1970,
                    stepResultsJSON,
                    variablesJSON,
                    execution.error,
                ])
            }
        } catch {
            log.error("Failed to save execution: \(error.localizedDescription)")
        }
    }
}

// MARK: - GRDB Row Initializers

extension WorkflowDefinition {
    init(row: Row) {
        id = row["id"] as? String ?? UUID().uuidString
        name = row["name"] as? String ?? ""
        description = row["description"] as? String ?? ""
        steps = WorkflowDefinition.decodeSteps(from: row["stepsJSON"] as? String ?? "[]")
        variables = WorkflowDefinition.decodeVariables(from: row["variablesJSON"] as? String ?? "[]")
        triggers = WorkflowDefinition.decodeTriggers(from: row["triggersJSON"] as? String ?? "[]")
        tags = row["tags"] as? String
        nextRunAt = (row["nextRunAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        createdAt = Date(timeIntervalSince1970: row["createdAt"] as? Double ?? 0)
        updatedAt = Date(timeIntervalSince1970: row["updatedAt"] as? Double ?? 0)
    }
}

extension WorkflowExecution {
    init(row: Row) {
        id = row["id"] as? String ?? UUID().uuidString
        workflowId = row["workflowId"] as? String ?? ""
        status = ExecutionStatus(rawValue: row["status"] as? String ?? "running") ?? .running
        startedAt = Date(timeIntervalSince1970: row["startedAt"] as? Double ?? 0)
        completedAt = (row["completedAt"] as? Double).map { Date(timeIntervalSince1970: $0) }
        stepResults = WorkflowExecution.decodeStepResults(from: row["stepResultsJSON"] as? String ?? "{}")
        variables = WorkflowExecution.decodeVariables(from: row["variablesJSON"] as? String ?? "{}")
        error = row["error"] as? String
    }
}
