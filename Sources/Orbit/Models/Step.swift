import Foundation

struct Step: Identifiable, Codable, Sendable {
    let id: String
    var name: String

    var stepType: StepType
    var toolName: String?
    var input: [String: String]
    var dependencies: [Int]
    var outputType: OutputType?

    var inputMapping: [String: String]
    var outputMapping: [String: String]
    var condition: String?
    var retryCount: Int
    var timeoutSeconds: Double?

    var status: StepStatus
    var result: String?

    enum StepType: String, Codable, Sendable {
        case action
        case research
        case generate
        case llm
        case screenshot
    }

    enum OutputType: String, Codable, Sendable {
        case markdown
        case presentation
        case document
        case spreadsheet
        case pdf
        case folder
        case code
    }

    enum StepStatus: String, Codable, Sendable {
        case pending
        case inProgress
        case completed
        case failed
    }

    static func tool(name: String, toolName: String, input: [String: String] = [:], dependencies: [Int] = []) -> Step {
        Step(id: UUID().uuidString, name: name, stepType: .action, toolName: toolName, input: input, dependencies: dependencies, outputType: nil, inputMapping: [:], outputMapping: [:], condition: nil, retryCount: 0, timeoutSeconds: nil, status: .pending, result: nil)
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        stepType: StepType = .action,
        toolName: String? = nil,
        input: [String: String] = [:],
        dependencies: [Int] = [],
        outputType: OutputType? = nil,
        inputMapping: [String: String] = [:],
        outputMapping: [String: String] = [:],
        condition: String? = nil,
        retryCount: Int = 0,
        timeoutSeconds: Double? = nil,
        status: StepStatus = .pending,
        result: String? = nil
    ) {
        self.id = id
        self.name = name
        self.stepType = stepType
        self.toolName = toolName
        self.input = input
        self.dependencies = dependencies
        self.outputType = outputType
        self.inputMapping = inputMapping
        self.outputMapping = outputMapping
        self.condition = condition
        self.retryCount = retryCount
        self.timeoutSeconds = timeoutSeconds
        self.status = status
        self.result = result
    }

    enum CodingKeys: String, CodingKey {
        case id, name, stepType, toolName, input, dependencies, outputType
        case inputMapping, outputMapping, condition, retryCount, timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        stepType = try container.decodeIfPresent(StepType.self, forKey: .stepType) ?? .action
        toolName = try container.decodeIfPresent(String.self, forKey: .toolName)
        input = try container.decodeIfPresent([String: String].self, forKey: .input) ?? [:]
        dependencies = try container.decodeIfPresent([Int].self, forKey: .dependencies) ?? []
        outputType = try container.decodeIfPresent(OutputType.self, forKey: .outputType)
        inputMapping = try container.decodeIfPresent([String: String].self, forKey: .inputMapping) ?? [:]
        outputMapping = try container.decodeIfPresent([String: String].self, forKey: .outputMapping) ?? [:]
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        retryCount = try container.decodeIfPresent(Int.self, forKey: .retryCount) ?? 0
        timeoutSeconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds)
        status = .pending
        result = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(stepType, forKey: .stepType)
        try container.encodeIfPresent(toolName, forKey: .toolName)
        try container.encode(input, forKey: .input)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encodeIfPresent(outputType, forKey: .outputType)
        try container.encode(inputMapping, forKey: .inputMapping)
        try container.encode(outputMapping, forKey: .outputMapping)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
    }
}

extension Step {
    static func decodePlanSteps(from json: String) -> [Step] {
        guard let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([Step].self, from: data) else { return [] }
        return steps
    }

    static func encodePlanSteps(_ steps: [Step]) -> String {
        guard let data = try? JSONEncoder().encode(steps),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }
}
