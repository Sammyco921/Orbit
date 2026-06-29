import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "autonomy")

final class AutonomyService {
    private let goalStore: GoalStore
    private let workflowEngine: WorkflowEngine
    private let toolService: ToolService
    private let memoryService: MemoryService
    private let llmService: LLMService
    private let checkpointManager: CheckpointManager
    private let eventBus: EventBus?

    private var runningGoalIds = Set<String>()

    init(
        goalStore: GoalStore,
        workflowEngine: WorkflowEngine,
        toolService: ToolService,
        memoryService: MemoryService,
        llmService: LLMService,
        checkpointManager: CheckpointManager,
        eventBus: EventBus? = nil
    ) {
        self.goalStore = goalStore
        self.workflowEngine = workflowEngine
        self.toolService = toolService
        self.memoryService = memoryService
        self.llmService = llmService
        self.checkpointManager = checkpointManager
        self.eventBus = eventBus
    }

    func createGoal(
        description: String,
        criteria: String? = nil,
        priority: Int = 5,
        intervalMinutes: Double? = nil,
        maxRuns: Int? = nil,
        tags: String? = nil
    ) -> PersistedGoal {
        let now = Date()
        var goal = PersistedGoal(
            description: description,
            criteria: criteria,
            priority: priority,
            intervalMinutes: intervalMinutes,
            nextRunAt: now,
            maxRuns: maxRuns,
            tags: tags
        )
        goalStore.save(goal)
        log.notice("Created goal '\(goal.id.prefix(8))': \(description.prefix(60))")
        return goal
    }

    func pauseGoal(id: String) {
        goalStore.updateStatus(id: id, status: .paused)
    }

    func resumeGoal(id: String) {
        goalStore.updateStatus(id: id, status: .active)
    }

    func completeGoal(id: String) {
        goalStore.updateStatus(id: id, status: .completed)
    }

    func failGoal(id: String) {
        goalStore.updateStatus(id: id, status: .failed)
    }

    func deleteGoal(id: String) {
        goalStore.delete(id: id)
    }

    func processDueGoals() async {
        let dueGoals = goalStore.dueGoals()
        for goal in dueGoals {
            guard !runningGoalIds.contains(goal.id) else { continue }
            guard goal.status == .active else { continue }

            if let max = goal.maxRuns, goal.runCount >= max {
                goalStore.updateStatus(id: goal.id, status: .completed)
                continue
            }

            runningGoalIds.insert(goal.id)
            await executeGoal(goal)
            runningGoalIds.remove(goal.id)
        }
    }

    func executeGoal(_ goal: PersistedGoal) async {
        let goalStart = CFAbsoluteTimeGetCurrent()
        eventBus?.publish(GoalStartedEvent(goalId: goal.id, description: goal.description, timestamp: Date()))
        log.notice("Executing goal '\(goal.id.prefix(8))': \(goal.description.prefix(60))")

        let provider = llmService.currentProvider()
        let context = await memoryService.contextMessages(
            query: goal.description,
            recentMessages: [],
            conversationId: goal.conversationId
        )

        let outcome: String

        do {
            var lastError: String?
            var lastSummary = ""

            let stream = workflowEngine.executeReAct(
                goalDescription: goal.description,
                maxSteps: 15,
                contextMessages: context,
                llm: provider,
                tools: toolService.toolRegistry,
                parameters: ModelParameters(),
                checkpointManager: checkpointManager,
                executionId: UUID().uuidString,
                conversationId: goal.conversationId,
                approvalMode: .autoApprove
            )

            for await event in stream {
                switch event {
                case .completed(let summary):
                    lastSummary = summary
                case .error(let error):
                    lastError = error
                case .toolResult:
                    break
                default:
                    break
                }
            }

            let duration = (CFAbsoluteTimeGetCurrent() - goalStart) * 1000
            if let error = lastError {
                outcome = "failed: \(error)"
                goalStore.recordRun(id: goal.id, outcome: outcome)
                eventBus?.publish(GoalCompletedEvent(goalId: goal.id, outcome: outcome, durationMs: duration, timestamp: Date()))
                log.error("Goal '\(goal.id.prefix(8))' failed: \(error)")
            } else {
                let summaryText = lastSummary.isEmpty ? "goal completed" : lastSummary
                outcome = "succeeded: \(summaryText)"
                goalStore.recordRun(id: goal.id, outcome: outcome)
                eventBus?.publish(GoalCompletedEvent(goalId: goal.id, outcome: outcome, durationMs: duration, timestamp: Date()))
                log.notice("Goal '\(goal.id.prefix(8))' succeeded\(lastSummary.isEmpty ? "" : ": \(lastSummary)")")
            }
        } catch {
            let duration = (CFAbsoluteTimeGetCurrent() - goalStart) * 1000
            outcome = "errored: \(error.localizedDescription)"
            goalStore.recordRun(id: goal.id, outcome: outcome)
            eventBus?.publish(GoalCompletedEvent(goalId: goal.id, outcome: outcome, durationMs: duration, timestamp: Date()))
            log.error("Goal '\(goal.id.prefix(8))' errored: \(error.localizedDescription)")
        }

        if let interval = goal.intervalMinutes, interval > 0 {
            let nextRun = Date().addingTimeInterval(interval * 60)
            goalStore.setNextRun(id: goal.id, nextRunAt: nextRun)
        } else {
            goalStore.updateStatus(id: goal.id, status: .completed)
        }
    }

    func goals() -> [PersistedGoal] {
        goalStore.allGoals()
    }

    func activeGoals() -> [PersistedGoal] {
        goalStore.activeGoals()
    }
}
