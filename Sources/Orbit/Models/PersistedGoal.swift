import Foundation

enum GoalStatus: String, Codable, Sendable {
    case active
    case paused
    case completed
    case failed
}

struct PersistedGoal: Identifiable, Codable, Sendable {
    let id: String
    var description: String
    var criteria: String?
    var status: GoalStatus
    var priority: Int
    var intervalMinutes: Double?
    var lastRunAt: Date?
    var nextRunAt: Date?
    var lastOutcome: String?
    var runCount: Int
    var maxRuns: Int?
    var tags: String?
    var createdAt: Date
    var updatedAt: Date
    var conversationId: String?

    init(
        id: String = UUID().uuidString,
        description: String,
        criteria: String? = nil,
        status: GoalStatus = .active,
        priority: Int = 5,
        intervalMinutes: Double? = nil,
        lastRunAt: Date? = nil,
        nextRunAt: Date? = nil,
        lastOutcome: String? = nil,
        runCount: Int = 0,
        maxRuns: Int? = nil,
        tags: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        conversationId: String? = nil
    ) {
        self.id = id
        self.description = description
        self.criteria = criteria
        self.status = status
        self.priority = priority
        self.intervalMinutes = intervalMinutes
        self.lastRunAt = lastRunAt
        self.nextRunAt = nextRunAt
        self.lastOutcome = lastOutcome
        self.runCount = runCount
        self.maxRuns = maxRuns
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.conversationId = conversationId
    }
}
