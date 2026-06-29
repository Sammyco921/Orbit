import Foundation

// MARK: - Install Template Tool

final class TemplateInstallTool: Tool {
    var definition = ToolDefinition(
        id: "templateInstall",
        name: "Install Template",
        description: "Install a workflow template. Creates a new WorkflowDefinition from the template with your variable values. Use 'templateList' to see available templates and their required variables.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "templateId", description: "The ID of the template to install", type: .string, required: true),
            ToolParameter(name: "variables", description: "JSON object of variable name-value pairs (e.g. {\"email\":\"user@example.com\"})", type: .string, required: true),
        ])
    )

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry) { self.registry = registry }

    func run(input: [String: String]) async throws -> String {
        guard let templateId = input["templateId"], !templateId.isEmpty else {
            return "No templateId specified."
        }

        guard let rawVars = input["variables"],
              let data = rawVars.data(using: .utf8),
              let userVars = try? JSONDecoder().decode([String: String].self, from: data) else {
            return "Invalid variables JSON. Provide a JSON object like {\"varName\":\"value\"}."
        }

        do {
            let result = try registry.install(templateId: templateId, variableValues: userVars)

            var output = "Template '\(result.template.name)' installed successfully."
            output += "\nWorkflow ID: \(result.workflow.id)"
            output += "\nWorkflow Name: \(result.workflow.name)"
            output += "\nSteps: \(result.workflow.steps.count)"
            output += "\nTriggers: \(result.workflow.triggers.map(\.type.rawValue).joined(separator: ", "))"
            if !result.resolvedVariables.isEmpty {
                output += "\nVariables:\n"
                for (k, v) in result.resolvedVariables.sorted(by: { $0.key < $1.key }) {
                    output += "  \(k) = \(v)\n"
                }
            }
            return output
        } catch let error as TemplateError {
            switch error {
            case .notFound(let id):
                return "Template '\(id)' not found. Use 'templateList' to see available templates."
            case .unresolvedVariables(let vars):
                let template = registry.template(id: templateId)
                let prompts = template?.variables.filter { vars.contains($0.name) }.map { v in
                    "  \(v.name): \(v.description)\(v.required ? " (required)" : " (optional)\(v.defaultValue.map { " default: \($0)" } ?? "")")"
                }.joined(separator: "\n") ?? ""
                return "Missing values for required variables:\n\(prompts)"
            case .validationFailed(let detail):
                return "Template validation failed: \(detail)"
            default:
                return "Installation failed: \(error.localizedDescription)"
            }
        } catch {
            return "Installation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - List Templates Tool

final class TemplateListTool: Tool {
    var definition = ToolDefinition(
        id: "templateList",
        name: "List Templates",
        description: "List all available workflow templates. You can filter by category or search by keyword. Shows built-in and user-installed templates.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "category", description: "Filter by category: email_digest, subscription_tracker, invoice_finder, github_backup, automation, custom", type: .string, required: false),
            ToolParameter(name: "search", description: "Search templates by name, description, or tags", type: .string, required: false),
        ])
    )

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry) { self.registry = registry }

    func run(input: [String: String]) async throws -> String {
        let templates: [WorkflowTemplate]
        if let search = input["search"], !search.isEmpty {
            templates = registry.search(search)
        } else if let categoryRaw = input["category"], let category = TemplateCategory(rawValue: categoryRaw) {
            templates = registry.templates(category: category)
        } else {
            templates = registry.allTemplates()
        }

        if templates.isEmpty {
            return "No templates found."
        }

        let installed = registry.listInstalled()
        let installedTemplateIds = Set(installed.map(\.record.templateId))

        var output = "Available Templates (\(templates.count)):\n"
        for t in templates.sorted(by: { $0.name < $1.name }) {
            let installedMarker = installedTemplateIds.contains(t.id) ? " ✓ Installed" : ""
            let builtInMarker = t.isBuiltIn ? " [Built-in]" : " [User]"
            output += "\n  \(t.name) (\(t.id))\(builtInMarker)\(installedMarker)"
            output += "\n  Category: \(t.category.displayName)  Version: \(t.version)  Author: \(t.author)"
            output += "\n  \(t.description)"
            if !t.tags.isEmpty {
                output += "\n  Tags: \(t.tags.joined(separator: ", "))"
            }
            if !t.variables.isEmpty {
                output += "\n  Variables:"
                for v in t.variables {
                    let req = v.required ? " (required)" : ""
                    let def = v.defaultValue.map { " [default: \($0)]" } ?? ""
                    output += "\n    • \(v.name): \(v.description)\(req)\(def)"
                }
            }
            output += "\n"
        }
        return output
    }
}

// MARK: - Delete Template Tool

final class TemplateDeleteTool: Tool {
    var definition = ToolDefinition(
        id: "templateDelete",
        name: "Delete Template",
        description: "Delete an installed template and its associated workflow(s). Provide the workflow ID (from 'templateList' or workflow list) or the template ID to uninstall all instances.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "workflowId", description: "The workflow ID to uninstall (get from 'templateList' installed templates or 'templateGetInfo')", type: .string, required: false),
            ToolParameter(name: "templateId", description: "Template ID to uninstall all instances of", type: .string, required: false),
        ])
    )

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry) { self.registry = registry }

    func run(input: [String: String]) async throws -> String {
        if let workflowId = input["workflowId"], !workflowId.isEmpty {
            if registry.uninstall(workflowId: workflowId) {
                return "Workflow '\(workflowId)' uninstalled."
            } else {
                return "No installation found for workflow '\(workflowId)'."
            }
        } else if let templateId = input["templateId"], !templateId.isEmpty {
            let wfIds = registry.uninstallByTemplateId(templateId)
            if wfIds.isEmpty {
                return "No installations found for template '\(templateId)'."
            }
            return "Uninstalled \(wfIds.count) workflow(s) for template '\(templateId)': \(wfIds.joined(separator: ", "))"
        } else {
            return "Specify either workflowId or templateId to delete."
        }
    }
}

// MARK: - Export Template Tool

final class TemplateExportTool: Tool {
    var definition = ToolDefinition(
        id: "templateExport",
        name: "Export Template",
        description: "Export a template as JSON. You can share or back up the exported JSON. Use 'templateImport' to import it elsewhere.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "templateId", description: "Template ID to export", type: .string, required: true),
        ])
    )

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry) { self.registry = registry }

    func run(input: [String: String]) async throws -> String {
        guard let templateId = input["templateId"], !templateId.isEmpty else {
            return "No templateId specified."
        }

        do {
            let json = try registry.export(templateId: templateId)
            return json
        } catch TemplateError.notFound(let id) {
            return "Template '\(id)' not found. Use 'templateList' to see available templates."
        } catch {
            return "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Import Template Tool

final class TemplateImportTool: Tool {
    var definition = ToolDefinition(
        id: "templateImport",
        name: "Import Template",
        description: "Import a template from its exported JSON. The template will be available for installation after import.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "json", description: "The exported template JSON", type: .string, required: true),
        ])
    )

    private let registry: TemplateRegistry

    init(registry: TemplateRegistry) { self.registry = registry }

    func run(input: [String: String]) async throws -> String {
        guard let json = input["json"], !json.isEmpty else {
            return "No JSON specified."
        }

        do {
            let template = try registry.import(from: json)
            registry.saveUserTemplates()
            return """
            Template imported successfully.
            Name: \(template.name)
            ID: \(template.id)
            Category: \(template.category.displayName)
            Author: \(template.author)
            Version: \(template.version)
            Steps: \(template.steps.count)
            Variables: \(template.variables.count)
            Use 'templateInstall' with this templateId to create a workflow from it.
            """
        } catch TemplateError.importFailed(let detail) {
            return "Import failed: \(detail)"
        } catch TemplateError.validationFailed(let detail) {
            return "Validation failed: \(detail)"
        } catch {
            return "Import failed: \(error.localizedDescription)"
        }
    }
}
