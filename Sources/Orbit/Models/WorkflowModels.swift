import Foundation

// MARK: - Workflow Definition

struct WorkflowDefinition: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var description: String
    var steps: [Step]
    var variables: [WorkflowVariable]
    var triggers: [WorkflowTrigger]
    var tags: String?
    var nextRunAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String = "",
        steps: [Step] = [],
        variables: [WorkflowVariable] = [],
        triggers: [WorkflowTrigger] = [],
        tags: String? = nil,
        nextRunAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.steps = steps
        self.variables = variables
        self.triggers = triggers
        self.tags = tags
        self.nextRunAt = nextRunAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct WorkflowVariable: Codable, Sendable {
    let name: String
    var defaultValue: String?
    var description: String?
    var required: Bool

    init(name: String, defaultValue: String? = nil, description: String? = nil, required: Bool = false) {
        self.name = name
        self.defaultValue = defaultValue
        self.description = description
        self.required = required
    }
}

struct WorkflowTrigger: Codable, Sendable {
    var type: TriggerType
    var schedule: String?
    var eventPattern: String?

    enum TriggerType: String, Codable, Sendable {
        case manual
        case scheduled
        case event
    }

    init(type: TriggerType = .manual, schedule: String? = nil, eventPattern: String? = nil) {
        self.type = type
        self.schedule = schedule
        self.eventPattern = eventPattern
    }
}

// MARK: - Workflow Execution

enum ExecutionStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

struct WorkflowExecution: Identifiable, Codable, Sendable {
    let id: String
    let workflowId: String
    var status: ExecutionStatus
    var startedAt: Date
    var completedAt: Date?
    var stepResults: [String: String]
    var variables: [String: String]
    var error: String?

    init(
        id: String = UUID().uuidString,
        workflowId: String,
        status: ExecutionStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        stepResults: [String: String] = [:],
        variables: [String: String] = [:],
        error: String? = nil
    ) {
        self.id = id
        self.workflowId = workflowId
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.stepResults = stepResults
        self.variables = variables
        self.error = error
    }
}

// MARK: - JSON Coding Helpers

extension WorkflowDefinition {
    static func decodeSteps(from json: String) -> [Step] {
        guard let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([Step].self, from: data) else { return [] }
        return steps
    }

    static func encodeSteps(_ steps: [Step]) -> String {
        guard let data = try? JSONEncoder().encode(steps),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeVariables(from json: String) -> [WorkflowVariable] {
        guard let data = json.data(using: .utf8),
              let vars = try? JSONDecoder().decode([WorkflowVariable].self, from: data) else { return [] }
        return vars
    }

    static func encodeVariables(_ variables: [WorkflowVariable]) -> String {
        guard let data = try? JSONEncoder().encode(variables),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    static func decodeTriggers(from json: String) -> [WorkflowTrigger] {
        guard let data = json.data(using: .utf8),
              let triggers = try? JSONDecoder().decode([WorkflowTrigger].self, from: data) else { return [] }
        return triggers
    }

    static func encodeTriggers(_ triggers: [WorkflowTrigger]) -> String {
        guard let data = try? JSONEncoder().encode(triggers),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}

extension WorkflowExecution {
    static func decodeStepResults(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func encodeStepResults(_ dict: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    static func decodeVariables(from json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func encodeVariables(_ dict: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }
}
