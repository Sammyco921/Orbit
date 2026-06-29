import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "templates")

final class TemplateStore {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    // MARK: - Installed Templates

    func allInstalled() -> [InstalledTemplateRecord] {
        do {
            return try db.read { database in
                try Row.fetchAll(database, sql: "SELECT * FROM installed_templates ORDER BY installedAt DESC").map(InstalledTemplateRecord.init(row:))
            }
        } catch {
            log.error("Failed to fetch installed templates: \(error.localizedDescription)")
            return []
        }
    }

    func installed(id: String) -> InstalledTemplateRecord? {
        do {
            return try db.read { database in
                guard let row = try Row.fetchOne(database, sql: "SELECT * FROM installed_templates WHERE id = ?", arguments: [id]) else { return nil }
                return InstalledTemplateRecord(row: row)
            }
        } catch {
            log.error("Failed to fetch installed template: \(error.localizedDescription)")
            return nil
        }
    }

    func installedByTemplateId(_ templateId: String) -> [InstalledTemplateRecord] {
        do {
            return try db.read { database in
                try Row.fetchAll(database, sql: "SELECT * FROM installed_templates WHERE templateId = ? ORDER BY installedAt DESC", arguments: [templateId]).map(InstalledTemplateRecord.init(row:))
            }
        } catch {
            log.error("Failed to fetch installed templates for template: \(error.localizedDescription)")
            return []
        }
    }

    func installedByWorkflowId(_ workflowId: String) -> InstalledTemplateRecord? {
        do {
            return try db.read { database in
                guard let row = try Row.fetchOne(database, sql: "SELECT * FROM installed_templates WHERE workflowId = ?", arguments: [workflowId]) else { return nil }
                return InstalledTemplateRecord(row: row)
            }
        } catch {
            log.error("Failed to fetch installed template for workflow: \(error.localizedDescription)")
            return nil
        }
    }

    func saveInstallation(_ record: InstalledTemplateRecord) {
        do {
            let variablesData = try JSONEncoder().encode(record.variables)
            let variablesJSON = String(data: variablesData, encoding: .utf8) ?? "{}"
            try db.write { database in
                try database.execute(sql: """
                    INSERT OR REPLACE INTO installed_templates (id, templateId, workflowId, installedAt, variablesJSON)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [
                    record.id,
                    record.templateId,
                    record.workflowId,
                    record.installedAt.timeIntervalSince1970,
                    variablesJSON,
                ])
            }
        } catch {
            log.error("Failed to save installation record: \(error.localizedDescription)")
        }
    }

    func deleteInstallation(id: String) {
        do {
            try db.write { database in
                try database.execute(sql: "DELETE FROM installed_templates WHERE id = ?", arguments: [id])
            }
        } catch {
            log.error("Failed to delete installation record: \(error.localizedDescription)")
        }
    }

    func deleteInstallationsByTemplateId(_ templateId: String) -> [InstalledTemplateRecord] {
        let records = installedByTemplateId(templateId)
        do {
            try db.write { database in
                try database.execute(sql: "DELETE FROM installed_templates WHERE templateId = ?", arguments: [templateId])
            }
        } catch {
            log.error("Failed to delete installation records: \(error.localizedDescription)")
        }
        return records
    }
}

// MARK: - GRDB Row Initializers

extension InstalledTemplateRecord {
    init(row: Row) {
        id = row["id"] as? String ?? UUID().uuidString
        templateId = row["templateId"] as? String ?? ""
        workflowId = row["workflowId"] as? String ?? ""
        installedAt = Date(timeIntervalSince1970: row["installedAt"] as? Double ?? 0)
        if let json = row["variablesJSON"] as? String,
           let data = json.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            variables = dict
        } else {
            variables = [:]
        }
    }
}
