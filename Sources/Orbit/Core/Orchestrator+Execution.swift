import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "persistence")

// MARK: - Plan Execution

extension Orchestrator {
    func approveCurrentPlan() async {
        guard let plan = currentPlan else { return }
        plan.status = .approved
        isProcessing = true
        await executePlanStreaming()
    }

    func rejectCurrentPlan() {
        guard let plan = currentPlan else { return }
        plan.status = .rejected
        addMessage(Message(role: .assistant, content: "Plan cancelled. How else can I help?"))
        currentPlan = nil
        isProcessing = false
    }

    private func executePlanStreaming() async {
        guard let plan = currentPlan else {
            addMessage(Message(role: .assistant, content: "No plan to execute."))
            isProcessing = false
            return
        }

        plan.status = .executing
        streamingText = ""
        isStreaming = true
        var artifacts: [Artifact] = []

        streamingText += "**Plan:** \(plan.summary)\n\n"
        for (i, step) in plan.steps.enumerated() {
            streamingText += "\(i + 1). \(step.name)\n"
        }
        streamingText += "\n"

        let stepServices = StepServices(
            research: runtime.researchService,
            document: runtime.documentService,
            memory: runtime.memoryService,
            llmProvider: currentProvider(),
            llmParameters: activeParameters(),
            messages: messages,
            conversationId: activeConversationId?.uuidString,
            workspaceId: activeWorkspaceId?.uuidString,
            workspaceName: activeWorkspace?.name,
            workspacePath: activeWorkspace?.path,
            workspaceKBIds: activeWorkspace?.knowledgeBaseIds,
            sanitizeFilename: { [weak self] in self?.sanitizeFilename(from: $0) ?? $0 },
            onToken: { [weak self] in self?.bufferStreamingChunk($0) },
            onProgress: { [weak self] in self?.streamingText += $0 },
            flushTokens: { [weak self] in self?.flushStreamBuffer() }
        )

        var replanCount = 0
        let maxReplans = 3
        let maxRetries = 3

        while replanCount <= maxReplans && !Task.isCancelled {
            let pending = plan.steps.filter { $0.status == .pending }
            guard !pending.isEmpty else { break }

            await runtime.workflowEngine.executeDAG(
                stepCount: plan.steps.count,
                dependencies: plan.steps.map { $0.dependencies },
                steps: &plan.steps,
                services: stepServices,
                artifacts: &artifacts,
                maxRetries: maxRetries,
                onStepEvent: { [weak self] index, status, attempt in
                    guard let self else { return }
                    plan.steps[index].status = status
                    switch status {
                    case .inProgress:
                        if attempt > 1 {
                            streamingText += "\n\n_Retrying (attempt \(attempt)/\(maxRetries))..._\n\n"
                        }
                    case .completed:
                        timelineLog.append(TimelineEntry(stepName: plan.steps[index].name, stepType: plan.steps[index].stepType.rawValue, attempt: attempt, outcome: "succeeded", detail: plan.steps[index].result ?? "Completed"))
                    case .failed:
                        timelineLog.append(TimelineEntry(stepName: plan.steps[index].name, stepType: plan.steps[index].stepType.rawValue, attempt: attempt, outcome: "failed", detail: plan.steps[index].result ?? "Unknown error"))
                        streamingText += "\n\n**Failed after \(maxRetries) attempts**\n\n"
                    default:
                        break
                    }
                }
            )

            let failed = plan.steps.filter { $0.status == .failed }
            guard !failed.isEmpty else { break }

            replanCount += 1
            guard replanCount <= maxReplans else {
                streamingText += "\n**Max replans reached (\(maxReplans)).**\n\n"
                break
            }

            streamingText += "\n**⚠️ Step failed — adapting...**\n\n"

            let completedSteps = plan.steps.filter { $0.status == .completed }.map {
                (description: $0.name, result: $0.result ?? "")
            }
            let failedSteps = failed.map {
                (description: $0.name, error: $0.result ?? "Unknown error")
            }
            let remainingSteps = plan.steps.filter { $0.status == .pending }.map {
                (description: $0.name, tool: $0.toolName ?? "")
            }

            let planGenerator = PlanGenerator(
                tools: runtime.toolService.toolRegistry,
                llm: currentProvider(),
                parameters: activeParameters()
            )

            let replanResult: PlanGenerationResult
            do {
                replanResult = try await planGenerator.generatePlan(
                    goal: plan.summary,
                    completedSteps: completedSteps,
                    failedSteps: failedSteps,
                    remainingSteps: remainingSteps
                )
            } catch {
                streamingText += "\n**Replanning failed:** \(error.localizedDescription)\n\n"
                break
            }

            guard case .plan(let revisedPlan) = replanResult else {
                streamingText += "\n**Replanning chose direct execution instead.**\n\n"
                break
            }

            streamingText += "\n**Revised plan:** \(revisedPlan.summary)\n\n"
            for step in revisedPlan.steps {
                streamingText += "  → \(step.description)\n"
            }
            streamingText += "\n"

            let completed = plan.steps.filter { $0.status == .completed }
            let offset = completed.count
            var newSteps = completed

            for gs in revisedPlan.steps {
                let step = Step(
                    name: gs.description,
                    stepType: .action,
                    toolName: gs.tool,
                    input: gs.input,
                    dependencies: gs.dependencies.map { $0 + offset }
                )
                newSteps.append(step)
            }
            plan.steps = newSteps
        }

        plan.status = Task.isCancelled ? .failed : .completed
        if !Task.isCancelled {
            finalizeStreaming(with: artifacts)
        }
    }
}
