import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "planner-agent")

final class PlannerAgent: Agent {
    private let runtime: OrbitRuntime
    private var subGoalRetryCounts: [String: Int] = [:]
    private var completedSubGoalIDs: Set<String> = []
    private var currentPlan: [SubGoal] = []
    private var duplicateCache: Set<String> = []

    private let maxSubGoalsPerPlan = 10
    private let maxRetriesPerSubGoal = 3
    private let maxTotalRetries = 10
    private var childTasks: [String: AgentTask] = [:]
    private var pendingResults: [UUID: AgentTaskResult] = [:]

    init(name: String, runtime: OrbitRuntime) {
        self.runtime = runtime
        super.init(
            name: name,
            type: .planner,
            capabilities: [
                AgentCapability(name: "goal_decomposition", description: "Breaks complex goals into manageable sub-goals"),
                AgentCapability(name: "task_assignment", description: "Assigns sub-goals to appropriate specialized agents"),
                AgentCapability(name: "progress_monitoring", description: "Tracks progress of all sub-agents"),
                AgentCapability(name: "replanning", description: "Re-plans when sub-goals fail"),
                AgentCapability(name: "loop_protection", description: "Detects duplicate tasks and caps retries"),
                AgentCapability(name: "failure_escalation", description: "Escalates unrecoverable failures to the user")
            ]
        )
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        let sharedMemoryScope = context.sharedMemoryScope ?? goal.prefix(40).description

        // Step 1: Decompose goal into sub-goals
        currentPlan = try await decomposeGoal(goal, context: context)
        guard !currentPlan.isEmpty else {
            return try await executeDirectly(goal: goal, context: context)
        }

        guard currentPlan.count <= maxSubGoalsPerPlan else {
            throw OrbitError.subGoalFailed(goal, "Goal decomposition produced \(currentPlan.count) sub-goals (max \(maxSubGoalsPerPlan)). Please narrow the goal.")
        }

        // Step 2: Save plan to shared memory
        if let sharedMemory = runtime.agentRegistry.sharedMemory {
            let planDescriptions = currentPlan.map { $0.description }
            await sharedMemory.write(planDescriptions, key: "plan", scope: sharedMemoryScope)
        }

        // Report plan to comm service
        if let comm = runtime.agentRegistry.communicationService {
            let planMsg = AgentMessage(from: id, to: nil, type: .statusUpdate, content: "Plan: \(currentPlan.map(\.description).joined(separator: " → "))", metadata: ["goal": goal, "subGoalCount": "\(currentPlan.count)"])
            await comm.broadcast(planMsg)
        }

        // Step 3: Execute sub-goals (respecting dependencies)
        var results: [String] = []
        var totalRetriesUsed = 0

        for subGoal in currentPlan {
            guard status != .cancelled else { throw CancellationError() }

            let subGoalKey = subGoal.description
            let retryCount = subGoalRetryCounts[subGoalKey, default: 0]

            if totalRetriesUsed >= maxTotalRetries {
                let escalation = "Maximum total retries (\(maxTotalRetries)) exceeded. Escalating to user."
                try escalateFailure(goal: goal, context: context, reason: escalation)
                throw OrbitError.subGoalFailed(subGoalKey, escalation)
            }

            if completedSubGoalIDs.contains(subGoalKey) {
                log.debug("Skipping already completed sub-goal: \(subGoalKey)")
                continue
            }

            if isDuplicate(subGoalKey) {
                log.warning("Duplicate sub-goal detected, skipping: \(subGoalKey)")
                continue
            }
            addToDuplicateCache(subGoalKey)

            let agent = try selectAgent(for: subGoal)
            let agentType = AgentType(rawValue: subGoal.assignedAgentType) ?? .executor
            let subContext = AgentTaskContext(
                conversationId: context.conversationId,
                relevantMessages: context.relevantMessages + results,
                artifacts: context.artifacts,
                additionalInstructions: context.additionalInstructions,
                executionId: context.executionId,
                sharedMemoryScope: sharedMemoryScope,
                parentGoalId: id
            )

            let task = AgentTask(
                description: subGoal.description,
                assignedAgentType: agentType,
                context: subContext,
                maxRetries: maxRetriesPerSubGoal
            )

            assignTask(task, to: agent)
            childTasks[agent.id] = task

            // Execute the agent with retry loop
            var lastError: String? = nil
            var attempt = 0
            let maxAttempts = maxRetriesPerSubGoal + 1

            while attempt < maxAttempts {
                guard status != .cancelled else { throw CancellationError() }
                attempt += 1

                if attempt > 1 {
                    log.notice("Retrying sub-goal '\(subGoalKey)' (attempt \(attempt)/\(maxAttempts))")
                    emit(.statusChanged(agentId: id, status: .running))
                    agent.cancel()
                }

                for await output in agent.start(goal: subGoal.description, context: subContext) {
                    guard status != .cancelled else { throw CancellationError() }
                    emit(.statusChanged(agentId: id, status: .running))
                }

                if agent.status == .completed {
                    let result = AgentTaskResult(
                        taskId: task.id,
                        summary: "Completed: \(subGoal.description)",
                        output: agent.output,
                        artifacts: [:],
                        error: nil
                    )
                    pendingResults[task.id] = result
                    completedTasks.append(result)
                    completedSubGoalIDs.insert(subGoalKey)
                    emit(.taskCompleted(taskId: task.id, result: result))
                    results.append("[\(agent.name)] \(agent.output)")

                    // Store result in shared memory
                    if let sharedMemory = runtime.agentRegistry.sharedMemory {
                        await sharedMemory.write(agent.output, key: "result_\(subGoalKey.prefix(20))", scope: sharedMemoryScope)
                    }

                    // Report completion via comm
                    if let comm = runtime.agentRegistry.communicationService {
                        let msg = AgentMessage(from: id, to: nil, type: .taskResult, content: "Completed: \(subGoalKey)", metadata: ["agentId": agent.id, "subGoal": subGoalKey])
                        await comm.broadcast(msg)
                    }

                    break
                } else {
                    lastError = agent.error ?? "Unknown error"
                    subGoalRetryCounts[subGoalKey, default: 0] += 1
                    totalRetriesUsed += 1
                    log.warning("Sub-goal '\(subGoalKey)' failed (attempt \(attempt)): \(lastError ?? "")")

                    if attempt >= maxAttempts {
                        // All retries exhausted — try replanning
                        if let revised = try? await replan(failedGoal: subGoal.description, error: lastError ?? "Unknown error", context: context) {
                            log.notice("Replanning sub-goal '\(subGoalKey)' -> '\(revised.description)'")
                            // Replace current sub-goal with revised one
                            currentPlan = currentPlan.map { $0.description == subGoalKey ? revised : $0 }

                            if let comm = runtime.agentRegistry.communicationService {
                                let replanMsg = AgentMessage(from: id, to: nil, type: .statusUpdate, content: "Replanned: \(subGoalKey) → \(revised.description)", metadata: ["original": subGoalKey, "revised": revised.description])
                                await comm.broadcast(replanMsg)
                            }

                            let retryAgent = try selectAgent(for: revised)
                            let retryType = AgentType(rawValue: revised.assignedAgentType) ?? .executor
                            let retryTask = AgentTask(
                                description: revised.description,
                                assignedAgentType: retryType,
                                context: subContext,
                                maxRetries: 1
                            )
                            assignTask(retryTask, to: retryAgent)
                            retryAgent.cancel()
                            for await output in retryAgent.start(goal: revised.description, context: subContext) {}
                            if retryAgent.status == .completed {
                                let result = AgentTaskResult(
                                    taskId: retryTask.id,
                                    summary: "Completed (re-plan): \(revised.description)",
                                    output: retryAgent.output,
                                    artifacts: [:],
                                    error: nil
                                )
                                pendingResults[retryTask.id] = result
                                completedTasks.append(result)
                                completedSubGoalIDs.insert(subGoalKey)
                                emit(.taskCompleted(taskId: retryTask.id, result: result))
                                results.append("[\(retryAgent.name)] \(retryAgent.output)")
                                break
                            }
                        }

                        // Replanning also failed — escalate
                        try escalateFailure(goal: goal, context: context, reason: subGoalKey, error: lastError)
                        emit(.taskFailed(taskId: task.id, error: lastError ?? "Unknown error"))
                        throw OrbitError.subGoalFailed(subGoal.description, lastError ?? "Unknown error")
                    }
                }
            }
        }

        // Step 4: Save final summary to shared memory
        if let sharedMemory = runtime.agentRegistry.sharedMemory {
            await sharedMemory.write(results.joined(separator: "\n\n"), key: "final_result", scope: sharedMemoryScope)
        }

        // Save multi-agent checkpoint with shared memory state
        let sharedMemoryData = await runtime.agentRegistry.sharedMemory?.exportState()
        saveMultiAgentCheckpoint(goal: goal, sharedMemoryData: sharedMemoryData)

        return results.joined(separator: "\n\n")
    }

    // MARK: - Checkpoint

    private func saveMultiAgentCheckpoint(goal: String, sharedMemoryData: Data? = nil) {
        let agentStates = children.reduce(into: [String: AgentCheckpointState]()) { dict, agent in
            dict[agent.id] = AgentCheckpointState(
                agentId: agent.id, agentType: agent.type.rawValue,
                status: agent.status.rawValue, currentGoal: agent.currentGoal,
                lastOutput: agent.output, error: agent.error,
                taskCount: agent.tasks.count
            )
        }
        let planRecords = currentPlan.map { subGoal in
            SubGoalRecord(
                description: subGoal.description,
                assignedAgentType: subGoal.assignedAgentType,
                status: completedSubGoalIDs.contains(subGoal.description) ? "completed" : "pending",
                retryCount: subGoalRetryCounts[subGoal.description, default: 0],
                error: nil
            )
        }
        let checkpoint = ExecutionCheckpoint(
            id: id, goalDescription: goal, messages: [],
            stepCount: completedTasks.count, toolFailures: [:],
            conversationId: nil, createdAt: Date(),
            agentStates: agentStates,
            completedSubGoals: Array(completedSubGoalIDs),
            subGoalRetryCounts: subGoalRetryCounts,
            plan: planRecords,
            sharedMemoryData: sharedMemoryData
        )
        try? runtime.checkpointManager.save(checkpoint)
    }

    // MARK: - Checkpoint Restoration

    /// Restores planner state from a saved checkpoint. Returns the restored results
    /// for resubmission. Does NOT re-execute — just restores in-memory state.
    func loadMultiAgentCheckpoint(from checkpoint: ExecutionCheckpoint) -> String? {
        guard let states = checkpoint.agentStates,
              let completed = checkpoint.completedSubGoals,
              let planRecords = checkpoint.plan else {
            log.warning("Multi-agent checkpoint missing required state fields")
            return nil
        }

        completedSubGoalIDs = Set(completed)
        subGoalRetryCounts = checkpoint.subGoalRetryCounts ?? [:]
        currentPlan = planRecords.map { record in
            SubGoal(description: record.description, assignedAgentType: record.assignedAgentType, dependencies: [])
        }

        // Restore shared memory
        if let sharedMemoryData = checkpoint.sharedMemoryData {
            Task {
                await runtime.agentRegistry.sharedMemory?.importState(sharedMemoryData)
            }
        }

        log.notice("Restored multi-agent checkpoint (\(completed.count) sub-goals completed)")
        return "Restored \(completed.count) completed sub-goals. Ready for resume."
    }

    // MARK: - Duplicate Detection

    private func isDuplicate(_ description: String) -> Bool {
        duplicateCache.contains(normalize(description))
    }

    private func addToDuplicateCache(_ description: String) {
        duplicateCache.insert(normalize(description))
    }

    private func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Failure Escalation

    private func escalateFailure(goal: String, context: AgentTaskContext, reason: String, error: String? = nil) throws {
        let message: String
        if let error {
            message = """
            ⚠️ Orbit was unable to complete the following goal after all retries:
            
            Goal: \(goal)
            Failed at: \(reason)
            Error: \(error)
            
            Suggestions:
            - Try rephrasing the goal
            - Break it into smaller, more specific steps
            - Check if required services (OAuth) are connected
            - Some operations may require manual intervention
            """
        } else {
            message = """
            ⚠️ Orbit encountered an issue with this goal:
            
            Goal: \(goal)
            Issue: \(reason)
            
            Please review and try again with a more specific request.
            """
        }

        // Store in shared memory for UI visibility
        Task {
            if let sharedMemory = runtime.agentRegistry.sharedMemory {
                await sharedMemory.write(message, key: "escalation_error", scope: context.sharedMemoryScope ?? goal)
            }
            // Broadcast escalation via comm service
            if let comm = runtime.agentRegistry.communicationService {
                let msg = AgentMessage(from: id, to: nil, type: .statusUpdate, content: "ESCALATION: \(reason)", metadata: ["goal": goal, "error": error ?? "retries exhausted"])
                await comm.broadcast(msg)
            }
        }

        log.error("Escalating failure: \(message)")
    }

    // MARK: - Private Types

    private struct SubGoalPlan: Codable {
        let subGoals: [SubGoal]
    }

    private struct SubGoal: Codable {
        let description: String
        let assignedAgentType: String
        let dependencies: [Int]
    }

    private struct RevisedGoal: Codable {
        let description: String
        let assignedAgentType: String
    }

    // Override to provide child task results for context
    private func completedTaskResults() -> [AgentTaskResult] {
        completedTasks
    }

    private func appendCompletedTask(_ result: AgentTaskResult) {
        completedTasks.append(result)
    }

    // MARK: - LLM Operations

    private func decomposeGoal(_ goal: String, context: AgentTaskContext) async throws -> [SubGoal] {
        let availableTypes = children.isEmpty
            ? AgentType.allCases.filter { $0 != .planner }.map { "\($0.rawValue) (\($0.displayName))" }.joined(separator: ", ")
            : children.map { "\($0.type.rawValue) (\($0.name))" }.joined(separator: ", ")

        let priorContext = completedSubGoalIDs.isEmpty ? "" : "\nAlready completed: \(completedSubGoalIDs.joined(separator: ", "))"
        let retryContext = subGoalRetryCounts.isEmpty ? "" : "\nRetry context: \(subGoalRetryCounts.map { "\($0.key): \($0.value) retries" }.joined(separator: ", "))"

        let prompt = """
        Decompose the following goal into sub-goals that can be executed by specialized agents.
        Max \(maxSubGoalsPerPlan) sub-goals.

        Available agent types: \(availableTypes)
        \(priorContext)\(retryContext)

        Goal: \(goal)

        Respond with a JSON object:
        {
          "subGoals": [
            { "description": "...", "assignedAgentType": "executor|researcher|reviewer|memoryManager", "dependencies": [0] }
          ]
        }

        Dependencies reference the index (0-based) of sub-goals that must complete first.
        An empty dependencies array means the sub-goal has no prerequisites.
        Avoid repeating already completed goals.
        """

        let response = try await llmCompletion(prompt: prompt)
        guard let data = response.data(using: .utf8),
              let plan = try? JSONDecoder().decode(SubGoalPlan.self, from: extractJSON(from: data)) else {
            return [SubGoal(description: goal, assignedAgentType: "executor", dependencies: [])]
        }
        return plan.subGoals
    }

    private func selectAgent(for subGoal: SubGoal) throws -> Agent {
        let type = AgentType(rawValue: subGoal.assignedAgentType) ?? .executor
        if let existing = children.first(where: { $0.type == type }) {
            return existing
        }
        let agent = runtime.agentRegistry.createAgent(type: type, name: type.displayName, runtime: runtime)
        addChild(agent)
        return agent
    }

    private func replan(failedGoal: String, error: String, context: AgentTaskContext) async throws -> SubGoal {
        let prompt = """
        A sub-goal failed. Propose a revised approach.

        Failed goal: \(failedGoal)
        Error: \(error)
        Already completed: \(completedSubGoalIDs.joined(separator: ", "))

        Respond with JSON:
        { "description": "...", "assignedAgentType": "executor|researcher|reviewer" }
        """

        let response = try await llmCompletion(prompt: prompt)
        guard let data = response.data(using: .utf8),
              let revised = try? JSONDecoder().decode(RevisedGoal.self, from: extractJSON(from: data)) else {
            throw OrbitError.replanFailed(failedGoal)
        }
        return SubGoal(description: revised.description, assignedAgentType: revised.assignedAgentType, dependencies: [])
    }

    private func executeDirectly(goal: String, context: AgentTaskContext) async throws -> String {
        let executor = children.first { $0.type == .executor }
            ?? runtime.agentRegistry.createAgent(type: .executor, name: "Executor", runtime: runtime)
        addChild(executor)

        for await output in executor.start(goal: goal, context: context) {
            guard status != .cancelled else { throw CancellationError() }
        }

        if executor.status == .completed {
            return executor.output
        }
        throw OrbitError.subGoalFailed(goal, executor.error ?? "Unknown error")
    }

    private func llmCompletion(prompt: String) async throws -> String {
        let provider = runtime.llmService.currentProvider()
        let messages = [LLMMessage(role: .user, content: prompt)]
        return try await provider.complete(messages: messages, parameters: .init(temperature: 0.3))
    }

    private func extractJSON(from data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else { return data }
        if let start = string.firstIndex(of: "{"),
           let end = string.lastIndex(of: "}") {
            return String(string[start...end]).data(using: .utf8) ?? data
        }
        return data
    }
}


