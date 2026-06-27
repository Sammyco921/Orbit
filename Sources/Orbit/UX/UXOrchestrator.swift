import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "ux")

private let defaultStepTimeout: UInt64 = 30_000_000_000   // 30s
private let llmTimeout: UInt64 = 25_000_000_000            // 25s

@Observable
final class UXOrchestrator {
    // MARK: - Observable State (derived from JobStore)

    private(set) var currentStory: ExecutionStory?
    private(set) var lastStory: ExecutionStory?
    private(set) var executionStartedAt: Date?
    private(set) var executionEndedAt: Date?
    private(set) var stateMachine = UXStateMachine()

    // MARK: - Callbacks

    var onAssistantResponse: ((String) -> Void)?
    var onIntentSubmitted: ((String) -> Void)?
    var onStoryComplete: ((ExecutionStory) -> Void)?
    var onExecutionRejected: (() -> Void)?
    var onExecutionFinished: ((ExecutionJob?) -> Void)?

    // MARK: - Dependencies

    private let kernel: ExecutionKernel
    private let llmService: LLMService?
    private let jobStore: JobStore
    private let executionLock = NSLock()
    private var executionTask: Task<Void, Never>?
    private var isCancelled = false

    // MARK: - Current Job Context

    private var currentJob: ExecutionJob?

    private var llmProvider: LLMProvider? {
        llmService?.currentProvider()
    }

    var state: UXState { stateMachine.state }
    var narrative: ExecutionStory? { currentStory }

    init(kernel: ExecutionKernel, llmService: LLMService? = nil, jobStore: JobStore? = nil) {
        self.kernel = kernel
        self.llmService = llmService
        self.jobStore = jobStore ?? JobStore(inMemory: true)
    }

    // MARK: - Submit

    func submit(intent: String) {
        submit(intent: intent, existingJobId: nil)
    }

    func submit(intent: String, existingJobId: UUID?) {
        guard stateMachine.canAcceptInput else {
            log.notice("UX: cannot accept input in state \(self.state.progressDescription)")
            return
        }
        guard executionLock.try() else {
            log.notice("UX: execution already in progress — rejecting duplicate")
            onExecutionRejected?()
            return
        }
        if state == .completed || state == .failed || state == .cancelled {
            stateMachine.transition(.reset)
        }

        // Create or reuse job
        let job: ExecutionJob
        if let existingId = existingJobId, let existing = try? jobStore.fetchJob(existingId) {
            job = existing
        } else {
            guard let created = try? jobStore.createJob(intent: intent, executionMode: .interactive) else {
                executionLock.unlock()
                log.error("UX: failed to create job")
                return
            }
            job = created
        }
        currentJob = job

        isCancelled = false
        executionStartedAt = Date()
        stateMachine.transition(.submitIntent)
        currentStory = ExecutionStory(id: job.storyId, intent: intent, executionStartedAt: executionStartedAt)
        lastStory = nil
        onIntentSubmitted?(intent)

        executionTask = Task { @MainActor in
            defer { executionLock.unlock() }
            await runLifecycle(intent: intent, job: job)
        }
    }

    // MARK: - Cancel

    func cancel() {
        guard stateMachine.isInterruptible else { return }
        isCancelled = true
        executionEndedAt = Date()
        currentStory?.executionEndedAt = executionEndedAt
        executionTask?.cancel()
        executionTask = nil
        stateMachine.transition(.cancel)

        if let jobId = currentJob?.jobId {
            try? jobStore.markJobCancelled(jobId: jobId)
            persistStepFinalStates()
        }

        markInProgressStepsCancelled()
        finalizeStory(intent: currentStory?.intent ?? "")
        persistJobIfTerminal()
        log.notice("UX: execution cancelled by user")
    }

    // MARK: - Reset

    func reset() {
        executionTask?.cancel()
        executionTask = nil
        isCancelled = false
        executionStartedAt = nil
        executionEndedAt = nil
        if state != .idle {
            lastStory = currentStory
        }
        currentStory = nil
        currentJob = nil
        stateMachine.transition(.reset)
    }

    // MARK: - Lifecycle

    private func runLifecycle(intent: String, job: ExecutionJob) async {
        // If the job already has persisted steps (from scheduler recovery or resume),
        // skip interpreting/planning and go directly to execution.
        let existingSteps = jobStore.fetchSteps(jobId: job.jobId)
        if !existingSteps.isEmpty {
            log.notice("UX: resuming job \(job.jobId) with \(existingSteps.count) existing steps")
            currentStory = ExecutionStory(id: job.storyId, intent: intent, steps: existingSteps, executionStartedAt: Date())
            // Fast-forward state machine to executing
            stateMachine.transition(.submitIntent)
            stateMachine.transition(.intentInterpreted)
            stateMachine.transition(.planGenerated(stepCount: existingSteps.count))
            // The job should already be RUNNING (set by scheduler)
            await runExistingSteps(job: job)
            return
        }

        await runInterpreting(intent: intent)
        guard !isCancelled else { return }

        await runPlanning(intent: intent)
        guard !isCancelled else { return }

        // PLANNED → RUNNING
        try? jobStore.markJobRunning(jobId: job.jobId)

        // Empty / malformed plan fallback
        if let story = currentStory, !story.steps.isEmpty {
            stateMachine.transition(.planGenerated(stepCount: story.steps.count))
            for step in story.steps {
                try? jobStore.appendStep(jobId: job.jobId, step: step)
            }
        } else {
            log.notice("UX: plan was empty — inserted fallback step")
            stateMachine.transition(.planGenerated(stepCount: 1))
            let fallback = StoryStep(order: 0, description: "Responding conversationally", actionSummary: "Orbit will handle this directly", expectedOutput: "Friendly response", toolID: "echo")
            appendStep(fallback)
            try? jobStore.appendStep(jobId: job.jobId, step: fallback)
            currentStory?.steps[0] = fallback
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        await runExistingSteps(job: job)

        guard !isCancelled else { return }

        try? await Task.sleep(nanoseconds: 350_000_000)
        executionEndedAt = Date()
        currentStory?.executionEndedAt = executionEndedAt

        // Finalize job state
        let allFailed = currentStory?.steps.allSatisfy { $0.status == .failed || $0.status == .timedOut } ?? true
        if allFailed {
            stateMachine.transition(.stepFailed("All steps failed"))
            try? jobStore.markJobFailed(jobId: job.jobId)
        } else {
            stateMachine.transition(.allStepsCompleted)
            try? jobStore.markJobCompleted(jobId: job.jobId)
        }

        finalizeStory(intent: intent)
        lastStory = currentStory
        persistJobIfTerminal()
        onExecutionFinished?(currentJob)
    }

    /// Execute steps that are already persisted (for scheduler resume/recovery).
    /// Skips steps that are already in a terminal state.
    private func runExistingSteps(job: ExecutionJob) async {
        guard let executingStory = currentStory else { return }

        for i in executingStory.steps.indices {
            guard !isCancelled else { return }

            // Skip steps that are already completed/failed/timedOut/cancelled
            let existingStatus = executingStory.steps[i].status
            if existingStatus.isTerminal {
                continue
            }

            if i > 0 { try? await Task.sleep(nanoseconds: 200_000_000) }

            var step = executingStory.steps[i]
            step.status = .inProgress
            step.timestamp = Date()
            updateStep(at: i, with: step)
            try? jobStore.updateStepOutput(jobId: job.jobId, stepIndex: i, output: step.output ?? "")

            try? await Task.sleep(nanoseconds: 250_000_000)

            do {
                try await executeStep(at: i, step: step, intent: job.intent)
                if Task.isCancelled || isCancelled { return }
                markStepCompleted(i, detail: nil)
                try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                    s.status = .completed
                    s.output = self.currentStory?.steps[safe: i]?.output
                }
                try? jobStore.updateJobStepIndex(jobId: job.jobId, stepIndex: i)
                stateMachine.transition(.stepCompleted)
                try? await Task.sleep(nanoseconds: 150_000_000)
            } catch let err as ExecutionError {
                switch err {
                case .toolTimedOut(let tool):
                    markStepTimedOut(i, detail: "Tool timed out: \(tool)")
                    try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                        s.status = .timedOut; s.detail = "Tool timed out: \(tool)"
                    }
                    log.notice("UX: step \(i) timed out — continuing")
                case .llmTimedOut:
                    markStepTimedOut(i, detail: "LLM did not respond in time")
                    try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                        s.status = .timedOut; s.detail = "LLM did not respond in time"
                    }
                    log.notice("UX: step \(i) LLM timed out — continuing")
                case .streamInterrupted:
                    if isCancelled { return }
                    markStepFailed(i, detail: "Response interrupted")
                    try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                        s.status = .failed; s.detail = "Response interrupted"
                    }
                    log.notice("UX: step \(i) stream interrupted — continuing")
                case .stepFailed(let reason):
                    markStepFailed(i, detail: reason)
                    try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                        s.status = .failed; s.detail = reason
                    }
                    log.notice("UX: step \(i) failed — continuing")
                }
            } catch {
                if isCancelled { return }
                markStepFailed(i, detail: error.localizedDescription)
                try? jobStore.updateStep(jobId: job.jobId, stepIndex: i) { s in
                    s.status = .failed; s.detail = error.localizedDescription
                }
                log.notice("UX: step \(i) threw \(error.localizedDescription) — continuing")
            }
        }
    }

    // MARK: - Interpreting

    private func runInterpreting(intent: String) async {
        log.notice("UX: interpreting — \"\(intent)\"")
        try? await Task.sleep(nanoseconds: 300_000_000)
        stateMachine.transition(.intentInterpreted)
    }

    // MARK: - Planning

    private func runPlanning(intent: String) async {
        log.notice("UX: planning")
        let steps = generateKeywordSteps(for: intent)
        currentStory?.steps = steps
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    // MARK: - Execute Step

    private func executeStep(at index: Int, step: StoryStep, intent: String) async throws {
        let toolID = step.toolID ?? "echo"

        if toolID == "echo", let provider = llmProvider {
            let response = try await respondConversationallyStreaming(intent: intent, provider: provider, stepIndex: index)
            markStepOutput(index, output: response)
            onAssistantResponse?(response)
            return
        }

        do {
            let result = try await withTimeout(defaultStepTimeout) { [weak self] in
                guard let self else { throw ExecutionError.stepFailed("Orchestrator deallocated") }
                return try await self.kernel.execute(intent: ExecutionIntent(
                    action: .tool(toolID),
                    input: [:],
                    sessionId: "ux-\(self.currentStory?.id.uuidString.prefix(8) ?? "????")",
                    conversationId: nil,
                    source: .user,
                    approvalMode: .interactive
                ))
            }
            markStepOutput(index, output: result.output)
        } catch is CancellationError {
            throw ExecutionError.toolTimedOut(toolID)
        } catch {
            // Fallback: try LLM if tool fails
            if let provider = llmProvider {
                let response = try await respondConversationallyStreaming(intent: intent, provider: provider, stepIndex: index)
                markStepOutput(index, output: response)
                onAssistantResponse?(response)
                return
            }
            throw ExecutionError.stepFailed(error.localizedDescription)
        }
    }

    // MARK: - Streaming

    private func respondConversationallyStreaming(intent: String, provider: LLMProvider, stepIndex: Int) async throws -> String {
        let systemPrompt = """
        You are Orbit, a helpful and friendly AI assistant. \
        Respond naturally and conversationally to the user. \
        Be concise but warm.
        """
        let messages = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: intent),
        ]

        var accumulated = ""
        var hasDeliveredFirstToken = false

        do {
            let stream = provider.completeStreaming(messages: messages)
            for try await token in stream {
                guard !isCancelled, !Task.isCancelled else {
                    throw ExecutionError.streamInterrupted
                }
                if !hasDeliveredFirstToken {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    hasDeliveredFirstToken = true
                }
                accumulated += token
                updateStepStreamedTokens(stepIndex, tokens: accumulated)
                if let jobId = currentJob?.jobId {
                    try? jobStore.updateStepStreamedTokens(jobId: jobId, stepIndex: stepIndex, tokens: accumulated)
                }
            }
        } catch let err as ExecutionError {
            throw err
        } catch {
            guard !isCancelled, !Task.isCancelled else {
                throw ExecutionError.streamInterrupted
            }
            throw ExecutionError.stepFailed("LLM stream error: \(error.localizedDescription)")
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        return accumulated
    }

    // MARK: - Timeout Utility

    private func withTimeout<T>(_ nanoseconds: UInt64, work: @escaping () async throws -> T) async throws -> T {
        let workTask = Task { try await work() }
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: nanoseconds)
            workTask.cancel()
        }
        defer { timeoutTask.cancel() }
        return try await workTask.value
    }

    // MARK: - Keyword Step Generation

    private func generateKeywordSteps(for intent: String) -> [StoryStep] {
        let lower = intent.lowercased()

        if lower.contains("screenshot") || (lower.contains("capture") && lower.contains("screen")) {
            return [
                StoryStep(order: 0, description: "Capturing the screen", actionSummary: "Take a screenshot of the current display", expectedOutput: "Screen capture image", toolID: "screenshot"),
                StoryStep(order: 1, description: "Processing the capture", actionSummary: "Analyze and prepare the screenshot", expectedOutput: "Processed image data", toolID: "imageAnalyze"),
            ]
        }

        if lower.contains("file") && (lower.contains("find") || lower.contains("search") || lower.contains("where")) {
            return [
                StoryStep(order: 0, description: "Searching the file system", actionSummary: "Search for matching files across the system", expectedOutput: "List of matching file paths", toolID: "finderSearch"),
                StoryStep(order: 1, description: "Reading file metadata", actionSummary: "Examine file details and contents", expectedOutput: "File information summary", toolID: "readFile"),
            ]
        }

        if lower.contains("git") || lower.contains("commit") || lower.contains("push") || lower.contains("pull") {
            var steps = [StoryStep]()
            steps.append(StoryStep(order: 0, description: "Checking repository status", actionSummary: "Run git status to see current state", expectedOutput: "Working tree status", toolID: "gitStatus"))
            if lower.contains("commit") {
                steps.append(StoryStep(order: steps.count, description: "Staging and committing changes", actionSummary: "Stage modified files and create a new commit", expectedOutput: "New commit created", toolID: "gitCommit"))
            }
            if lower.contains("push") {
                steps.append(StoryStep(order: steps.count, description: "Pushing to remote repository", actionSummary: "Upload committed changes to remote", expectedOutput: "Changes pushed", toolID: "gitPush"))
            }
            return steps
        }

        if lower.contains("browser") || lower.contains("web") || lower.contains("internet") || lower.contains("search") {
            return [
                StoryStep(order: 0, description: "Opening web browser", actionSummary: "Launch browser and navigate to the target", expectedOutput: "Page loaded", toolID: "browserNavigate"),
                StoryStep(order: 1, description: "Reading page content", actionSummary: "Extract relevant information from the page", expectedOutput: "Page content", toolID: "browserExtract"),
                StoryStep(order: 2, description: "Summarizing findings", actionSummary: "Compile and organize the retrieved information", expectedOutput: "Structured summary", toolID: "echo"),
            ]
        }

        if lower.contains("write") || lower.contains("create") || lower.contains("make") || lower.contains("save") {
            return [
                StoryStep(order: 0, description: "Preparing content", actionSummary: "Organize and format the content to be written", expectedOutput: "Formatted content", toolID: "echo"),
                StoryStep(order: 1, description: "Writing to file", actionSummary: "Save the content to the specified location", expectedOutput: "File saved", toolID: "fileWrite"),
            ]
        }

        return [
            StoryStep(order: 0, description: "Responding to you", actionSummary: "Generate a friendly, helpful response", expectedOutput: "Conversational response", toolID: "echo"),
        ]
    }

    // MARK: - Finalization

    private func finalizeStory(intent: String) {
        guard var story = currentStory else { return }

        for i in story.steps.indices {
            switch story.steps[i].status {
            case .inProgress:
                story.steps[i].status = isCancelled ? .cancelled : .failed
                story.steps[i].detail = story.steps[i].detail ?? (isCancelled ? "Interrupted by cancellation" : "Interrupted")
            case .pending:
                story.steps[i].status = .cancelled
                story.steps[i].detail = "Not executed"
            default:
                break
            }
        }

        story.executionEndedAt = executionEndedAt ?? Date()

        if story.summary == nil {
            buildSummary(intent: intent, story: &story)
        }

        currentStory = story
    }

    // MARK: - Summary

    private func buildSummary(intent: String) {
        guard var story = currentStory else { return }
        buildSummary(intent: intent, story: &story)
        currentStory = story
    }

    private func buildSummary(intent: String, story: inout ExecutionStory) {
        let stepCount = story.steps.count
        let completedCount = story.steps.filter { $0.status == .completed }.count
        let failedCount = story.steps.filter { $0.status == .failed || $0.status == .timedOut }.count
        let cancelledCount = story.steps.filter { $0.status == .cancelled }.count
        let cancelledAt = story.cancelledAtIndex

        let whatWasDone: String
        let resultSummary: String

        if cancelledCount > 0 {
            let atStep = (cancelledAt ?? stepCount - 1) + 1
            whatWasDone = "Cancelled at step \(atStep) of \(stepCount)"
            resultSummary = cancelledCount > 0
                ? "Cancelled with \(completedCount) step\(completedCount != 1 ? "s" : "") completed."
                : "Cancelled before any steps completed."
        } else if state == .failed || (completedCount == 0 && failedCount > 0) {
            whatWasDone = "Failed — \(failedCount) step\(failedCount != 1 ? "s" : "") failed out of \(stepCount)"
            resultSummary = "\(failedCount) step\(failedCount != 1 ? "s" : "") failed."
        } else if failedCount > 0 {
            whatWasDone = "Completed with \(failedCount) partial failure\(failedCount != 1 ? "s" : "")"
            resultSummary = "\(completedCount) of \(stepCount) step\(stepCount != 1 ? "s" : "") succeeded. \(failedCount) failed."
        } else {
            whatWasDone = "Completed \(completedCount) of \(stepCount) step\(stepCount != 1 ? "s" : "")"
            resultSummary = "All \(completedCount) step\(completedCount != 1 ? "s" : "") completed successfully."
        }

        story.summary = SummarySection(
            whatWasDone: whatWasDone,
            whyItWasDone: "You asked: \"\(intent)\"",
            resultSummary: resultSummary
        )
    }

    // MARK: - Step Mutations

    private func appendStep(_ step: StoryStep) {
        guard var story = currentStory else { return }
        story.steps.append(step)
        currentStory = story
    }

    private func updateStep(at index: Int, with step: StoryStep) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        story.steps[index] = step
        currentStory = story
    }

    private func updateStepStreamedTokens(_ index: Int, tokens: String) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        story.steps[index].streamedTokens = tokens
        currentStory = story
    }

    private func markStepCompleted(_ index: Int, detail: String?) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        var step = story.steps[index]
        step.status = .completed
        if let d = detail { step.detail = d }
        story.steps[index] = step
        currentStory = story
    }

    private func markStepFailed(_ index: Int, detail: String?) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        var step = story.steps[index]
        step.status = .failed
        if let d = detail { step.detail = d }
        story.steps[index] = step
        currentStory = story
    }

    private func markStepTimedOut(_ index: Int, detail: String?) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        var step = story.steps[index]
        step.status = .timedOut
        if let d = detail { step.detail = d }
        story.steps[index] = step
        currentStory = story
    }

    private func markStepCancelled(_ index: Int, detail: String?) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        var step = story.steps[index]
        step.status = .cancelled
        if let d = detail { step.detail = d }
        story.steps[index] = step
        currentStory = story
    }

    private func markStepOutput(_ index: Int, output: String) {
        guard var story = currentStory, story.steps.indices.contains(index) else { return }
        story.steps[index].output = output
        currentStory = story
    }

    private func markInProgressStepsCancelled() {
        guard var story = currentStory else { return }
        for i in story.steps.indices where story.steps[i].status == .inProgress {
            story.steps[i].status = .cancelled
            story.steps[i].detail = "Cancelled by user"
        }
        currentStory = story
    }

    private func persistStepFinalStates() {
        guard let jobId = currentJob?.jobId, let story = currentStory else { return }
        for i in story.steps.indices {
            let step = story.steps[i]
            try? jobStore.updateStep(jobId: jobId, stepIndex: i) { s in
                s.status = step.status
                s.detail = step.detail
                s.output = step.output
            }
        }
    }

    private func persistJobIfTerminal() {
        guard let story = currentStory else { return }
        if state == .completed || state == .failed || state == .cancelled {
            onStoryComplete?(story)
        }
    }
}

// MARK: - Safe Collection Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

// MARK: - Story convenience accessors

extension ExecutionStory {
    var result: ResultSection? {
        guard let last = steps.last, let out = last.output else { return nil }
        return ResultSection(content: out)
    }

    var plan: [StoryStep] { steps }
}
