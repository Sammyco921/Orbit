import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "templates")

final class TemplateRegistry {
    private var builtInTemplates: [String: WorkflowTemplate] = [:]
    private var userTemplates: [String: WorkflowTemplate] = [:]
    private let userTemplatesDirectory: URL
    private let store: TemplateStore
    private let workflowStore: WorkflowStore

    init(store: TemplateStore, workflowStore: WorkflowStore) {
        self.store = store
        self.workflowStore = workflowStore

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.userTemplatesDirectory = appSupport.appendingPathComponent("com.orbit.user.templates", isDirectory: true)
        try? FileManager.default.createDirectory(at: userTemplatesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Registration

    func registerBuiltIn(_ templates: [WorkflowTemplate]) {
        for template in templates {
            builtInTemplates[template.id] = template
        }
        log.notice("Registered \(templates.count) built-in templates")
    }

    // MARK: - Query

    func allTemplates() -> [WorkflowTemplate] {
        let builtIn = Array(builtInTemplates.values)
        let user = Array(userTemplates.values)
        return builtIn + user
    }

    func template(id: String) -> WorkflowTemplate? {
        builtInTemplates[id] ?? userTemplates[id]
    }

    func templates(category: TemplateCategory) -> [WorkflowTemplate] {
        allTemplates().filter { $0.category == category }
    }

    func search(_ query: String) -> [WorkflowTemplate] {
        let lower = query.lowercased()
        return allTemplates().filter { template in
            template.name.lowercased().contains(lower) ||
            template.description.lowercased().contains(lower) ||
            template.tags.contains { $0.lowercased().contains(lower) }
        }
    }

    // MARK: - Install

    func install(templateId: String, variableValues: [String: String]) throws -> TemplateInstallResult {
        guard var template = template(id: templateId) else {
            throw TemplateError.notFound(templateId)
        }

        try template.validate()

        let unresolved = template.detectUnresolvedVariables(in: variableValues)
        if !unresolved.isEmpty {
            throw TemplateError.unresolvedVariables(unresolved)
        }

        let workflowDefinition = template.toWorkflowDefinition(variableValues: variableValues)

        workflowStore.saveDefinition(workflowDefinition)

        let record = InstalledTemplateRecord(
            templateId: template.id,
            workflowId: workflowDefinition.id,
            variables: variableValues
        )
        store.saveInstallation(record)

        let resolved = template.substituteVariables(variableValues)

        log.notice("Installed template '\(template.name)' as workflow '\(workflowDefinition.name)' (\(workflowDefinition.id))")

        return TemplateInstallResult(
            template: resolved,
            workflow: workflowDefinition,
            record: record,
            resolvedVariables: variableValues
        )
    }

    // MARK: - Uninstall

    func uninstall(workflowId: String) -> Bool {
        guard let record = store.installedByWorkflowId(workflowId) else {
            log.warning("No installation record found for workflow \(workflowId)")
            return false
        }

        store.deleteInstallation(id: record.id)
        workflowStore.deleteDefinition(id: workflowId)
        log.notice("Uninstalled template '\(record.templateId)' (workflow \(workflowId))")
        return true
    }

    func uninstallByTemplateId(_ templateId: String) -> [String] {
        let records = store.deleteInstallationsByTemplateId(templateId)
        let workflowIds = records.map(\.workflowId)
        for wfId in workflowIds {
            workflowStore.deleteDefinition(id: wfId)
        }
        log.notice("Uninstalled \(records.count) installations of template '\(templateId)'")
        return workflowIds
    }

    // MARK: - List

    func listInstalled() -> [(template: WorkflowTemplate, record: InstalledTemplateRecord)] {
        let records = store.allInstalled()
        var result: [(WorkflowTemplate, InstalledTemplateRecord)] = []
        for record in records {
            if let template = self.template(id: record.templateId) {
                result.append((template, record))
            } else {
                let workflow = workflowStore.definition(id: record.workflowId)
                let unknownTemplate = WorkflowTemplate(
                    id: record.templateId,
                    name: workflow?.name ?? record.templateId,
                    description: workflow?.description ?? "Template not found",
                    isBuiltIn: false
                )
                result.append((unknownTemplate, record))
            }
        }
        return result
    }

    // MARK: - Export

    func export(templateId: String) throws -> String {
        guard let template = template(id: templateId) else {
            throw TemplateError.notFound(templateId)
        }

        let payload = TemplateExportPayload(
            template: template,
            exportedAt: Date(),
            orbitVersion: "1.0.0"
        )

        guard let json = TemplateExportPayload.encode(payload) else {
            throw TemplateError.exportFailed
        }

        return json
    }

    // MARK: - Import

    func `import`(from json: String) throws -> WorkflowTemplate {
        guard let payload = TemplateExportPayload.decode(from: json) else {
            throw TemplateError.importFailed("Invalid JSON payload")
        }

        var template = payload.template
        template.isBuiltIn = false

        try template.validate()

        let importId = "imported_\(template.id)_\(UUID().uuidString.prefix(8))"
        template = WorkflowTemplate(
            id: importId,
            name: template.name,
            description: template.description,
            author: template.author,
            version: template.version,
            tags: template.tags,
            category: template.category,
            variables: template.variables,
            steps: template.steps,
            triggers: template.triggers,
            isBuiltIn: false
        )

        userTemplates[template.id] = template
        log.notice("Imported template '\(template.name)' (\(template.id))")

        return template
    }

    // MARK: - User Template Persistence

    func saveUserTemplates() {
        for (_, template) in userTemplates {
            saveUserTemplateToDisk(template)
        }
    }

    func loadUserTemplates() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: userTemplatesDirectory, includingPropertiesForKeys: nil) else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let json = String(data: data, encoding: .utf8),
                  let payload = TemplateExportPayload.decode(from: json) else { continue }

            var template = payload.template
            template.isBuiltIn = false
            self.userTemplates[template.id] = template
        }

        log.notice("Loaded \(self.userTemplates.count) user templates from disk")
    }

    private func saveUserTemplateToDisk(_ template: WorkflowTemplate) {
        let payload = TemplateExportPayload(
            template: template,
            exportedAt: Date(),
            orbitVersion: "1.0.0"
        )

        guard let json = TemplateExportPayload.encode(payload),
              let data = json.data(using: .utf8) else { return }

        let fileURL = userTemplatesDirectory.appendingPathComponent("\(template.id).json")
        try? data.write(to: fileURL)
    }
}

// MARK: - Template Error

enum TemplateError: LocalizedError, Sendable {
    case notFound(String)
    case unresolvedVariables(Set<String>)
    case exportFailed
    case importFailed(String)
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id): return "Template not found: \(id)"
        case .unresolvedVariables(let vars): return "Unresolved variables: \(vars.joined(separator: ", "))"
        case .exportFailed: return "Failed to export template"
        case .importFailed(let detail): return "Import failed: \(detail)"
        case .validationFailed(let detail): return "Validation failed: \(detail)"
        }
    }
}
