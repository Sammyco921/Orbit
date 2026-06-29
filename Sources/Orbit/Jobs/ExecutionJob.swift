import Foundation

// MARK: - Job State Machine

enum JobState: String, Codable, Sendable, CaseIterable {
    case created = "CREATED"
    case queued = "QUEUED"
    case running = "RUNNING"
    case paused = "PAUSED"
    case completed = "COMPLETED"
    case failed = "FAILED"
    case cancelled = "CANCELLED"

    static let validTransitions: [JobState: [JobState]] = [
        .created: [.queued, .cancelled],
        .queued: [.running, .cancelled],
        .running: [.completed, .failed, .cancelled, .paused],
        .paused: [.running, .cancelled],
        .completed: [],
        .failed: [],
        .cancelled: [],
    ]

    func canTransition(to next: JobState) -> Bool {
        Self.validTransitions[self]?.contains(next) ?? false
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        case .created, .queued, .running, .paused: false
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .running, .paused: true
        case .created, .completed, .failed, .cancelled: false
        }
    }
}

// MARK: - Execution Mode

enum ExecutionMode: String, Codable, Sendable {
    case interactive
    case background
    case menuBar
}

// MARK: - Execution Job Model

struct ExecutionJob: Identifiable, Codable, Sendable {
    var id: UUID { jobId }
    let jobId: UUID
    var storyId: UUID
    let intent: String
    var state: JobState
    let createdAt: Date
    var updatedAt: Date
    var currentStepIndex: Int
    let executionMode: ExecutionMode
    var retryCount: Int
    var lastHeartbeatAt: Date?
    var queuePosition: Int

    init(
        jobId: UUID = UUID(),
        storyId: UUID = UUID(),
        intent: String,
        state: JobState = .created,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        currentStepIndex: Int = 0,
        executionMode: ExecutionMode = .interactive,
        retryCount: Int = 0,
        lastHeartbeatAt: Date? = nil,
        queuePosition: Int = 0
    ) {
        self.jobId = jobId
        self.storyId = storyId
        self.intent = intent
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentStepIndex = currentStepIndex
        self.executionMode = executionMode
        self.retryCount = retryCount
        self.lastHeartbeatAt = lastHeartbeatAt
        self.queuePosition = queuePosition
    }
}
