import Foundation

// MARK: - Template Category

enum TemplateCategory: String, Codable, Sendable, CaseIterable {
    case emailDigest = "email_digest"
    case subscriptionTracker = "subscription_tracker"
    case invoiceFinder = "invoice_finder"
    case githubBackup = "github_backup"
    case automation
    case custom

    var displayName: String {
        switch self {
        case .emailDigest: return "Email Digest"
        case .subscriptionTracker: return "Subscription Tracker"
        case .invoiceFinder: return "Invoice Finder"
        case .githubBackup: return "GitHub Backup"
        case .automation: return "Automation"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Template Variable

struct TemplateVariable: Codable, Sendable, Equatable {
    let name: String
    let description: String
    let required: Bool
    let defaultValue: String?
    let prompt: String?

    init(name: String, description: String, required: Bool = true, defaultValue: String? = nil, prompt: String? = nil) {
        self.name = name
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
        self.prompt = prompt
    }
}

// MARK: - Workflow Template

struct WorkflowTemplate: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let author: String
    let version: String
    let tags: [String]
    let category: TemplateCategory
    let variables: [TemplateVariable]
    let steps: [Step]
    let triggers: [WorkflowTrigger]
    var isBuiltIn: Bool

    init(
        id: String,
        name: String,
        description: String,
        author: String = "Orbit",
        version: String = "1.0.0",
        tags: [String] = [],
        category: TemplateCategory = .custom,
        variables: [TemplateVariable] = [],
        steps: [Step] = [],
        triggers: [WorkflowTrigger] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.tags = tags
        self.category = category
        self.variables = variables
        self.steps = steps
        self.triggers = triggers
        self.isBuiltIn = isBuiltIn
    }

    static func variablePrompt(_ variable: TemplateVariable) -> String {
        let required = variable.required ? " (required)" : " (optional)"
        let defaultValue = variable.defaultValue.map { " [default: \($0)]" } ?? ""
        return "\(variable.description)\(required)\(defaultValue)"
    }
}

// MARK: - Installed Template Record

struct InstalledTemplateRecord: Identifiable, Codable, Sendable {
    let id: String
    let templateId: String
    let workflowId: String
    let installedAt: Date
    let variables: [String: String]

    init(id: String = UUID().uuidString, templateId: String, workflowId: String, installedAt: Date = Date(), variables: [String: String] = [:]) {
        self.id = id
        self.templateId = templateId
        self.workflowId = workflowId
        self.installedAt = installedAt
        self.variables = variables
    }
}

// MARK: - Template Install Result

struct TemplateInstallResult: Sendable {
    let template: WorkflowTemplate
    let workflow: WorkflowDefinition
    let record: InstalledTemplateRecord
    let resolvedVariables: [String: String]
}

// MARK: - Template Export Payload

struct TemplateExportPayload: Codable, Sendable {
    let template: WorkflowTemplate
    let exportedAt: Date
    let orbitVersion: String

    static func encode(_ payload: TemplateExportPayload) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String) -> TemplateExportPayload? {
        guard let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TemplateExportPayload.self, from: data) else { return nil }
        return payload
    }
}

// MARK: - Substitution Helpers

extension WorkflowTemplate {
    func substituteVariables(_ values: [String: String]) -> WorkflowTemplate {
        let substitutedSteps = steps.map { step -> Step in
            var s = step
            s.input = s.input.mapValues { applySubstitutions($0, values) }
            s.inputMapping = s.inputMapping.mapValues { applySubstitutions($0, values) }
            s.outputMapping = s.outputMapping.mapValues { applySubstitutions($0, values) }
            if let condition = s.condition {
                s.condition = applySubstitutions(condition, values)
            }
            if let toolName = s.toolName {
                s.toolName = applySubstitutions(toolName, values)
            }
            return s
        }

        let substitutedTriggers = triggers.map { trigger -> WorkflowTrigger in
            var t = trigger
            if let schedule = t.schedule {
                t.schedule = applySubstitutions(schedule, values)
            }
            if let pattern = t.eventPattern {
                t.eventPattern = applySubstitutions(pattern, values)
            }
            return t
        }

        return WorkflowTemplate(
            id: id,
            name: applySubstitutions(name, values),
            description: applySubstitutions(description, values),
            author: author,
            version: version,
            tags: tags.map { applySubstitutions($0, values) },
            category: category,
            variables: variables,
            steps: substitutedSteps,
            triggers: substitutedTriggers,
            isBuiltIn: isBuiltIn
        )
    }

    func toWorkflowDefinition(variableValues: [String: String]) -> WorkflowDefinition {
        let substituted = substituteVariables(variableValues)
        let workflowVariables = variables.map { tv -> WorkflowVariable in
            WorkflowVariable(
                name: tv.name,
                defaultValue: variableValues[tv.name] ?? tv.defaultValue,
                description: tv.description,
                required: tv.required
            )
        }

        return WorkflowDefinition(
            id: UUID().uuidString,
            name: substituted.name,
            description: substituted.description,
            steps: substituted.steps,
            variables: workflowVariables,
            triggers: substituted.triggers,
            tags: substituted.tags.joined(separator: ","),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    func collectVariablePrompts() -> [(variable: TemplateVariable, resolvedValue: String?)] {
        variables.map { v in
            (v, v.defaultValue)
        }
    }
}

private func applySubstitutions(_ input: String, _ values: [String: String]) -> String {
    var result = input
    for (key, value) in values {
        result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
    }
    return result
}

// MARK: - Template Validation

enum TemplateValidationError: LocalizedError, Sendable {
    case missingField(String)
    case invalidSteps(String)
    case duplicateVariable(String)
    case unresolvedVariables(Set<String>)

    var errorDescription: String? {
        switch self {
        case .missingField(let field): return "Missing required field: \(field)"
        case .invalidSteps(let detail): return "Invalid step configuration: \(detail)"
        case .duplicateVariable(let name): return "Duplicate variable: \(name)"
        case .unresolvedVariables(let vars): return "Unresolved variables: \(vars.joined(separator: ", "))"
        }
    }
}

extension WorkflowTemplate {
    func validate() throws {
        guard !id.isEmpty else { throw TemplateValidationError.missingField("id") }
        guard !name.isEmpty else { throw TemplateValidationError.missingField("name") }
        guard !steps.isEmpty else { throw TemplateValidationError.invalidSteps("At least one step is required") }

        let variableNames = Set(variables.map(\.name))
        if variableNames.count != variables.count {
            let dupes = Dictionary(grouping: variables, by: \.name).filter { $0.value.count > 1 }
            throw TemplateValidationError.duplicateVariable(dupes.keys.first ?? "")
        }

        for (index, step) in steps.enumerated() {
            guard !step.name.isEmpty else {
                throw TemplateValidationError.invalidSteps("Step \(index) has no name")
            }
            guard step.toolName != nil || step.stepType == .llm || step.stepType == .generate else {
                throw TemplateValidationError.invalidSteps("Step '\(step.name)' has no toolName and is not a generated step")
            }
        }
    }

    func detectUnresolvedVariables(in values: [String: String]) -> Set<String> {
        let pattern = try! NSRegularExpression(pattern: "\\{\\{\\s*(\\w+)\\s*\\}\\}")
        var found = Set<String>()

        let textsToCheck = [name, description] + tags + steps.flatMap { step -> [String] in
            var texts = [step.name] + Array(step.input.values) + Array(step.inputMapping.values) + Array(step.outputMapping.values)
            if let condition = step.condition { texts.append(condition) }
            if let toolName = step.toolName { texts.append(toolName) }
            return texts
        } + triggers.compactMap { $0.schedule } + triggers.compactMap { $0.eventPattern }

        for text in textsToCheck {
            let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let range = Range(match.range(at: 1), in: text) {
                    let varName = String(text[range])
                    found.insert(varName)
                }
            }
        }

        let providedKeys = Set(values.keys)
        let defaultedKeys = Set(variables.filter { $0.defaultValue != nil }.map(\.name))
        return found.subtracting(providedKeys).subtracting(defaultedKeys)
    }
}
