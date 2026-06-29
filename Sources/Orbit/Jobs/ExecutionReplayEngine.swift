import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "replay")

/// Reconstructs full executions from Job + Story data.
///
/// Supports deterministic replay for debugging and
/// step-by-step inspection for future UI use.
final class ExecutionReplayEngine {
    private let jobStore: JobStore

    init(jobStore: JobStore) {
        self.jobStore = jobStore
    }

    // MARK: - Reconstruction

    /// Reconstruct a full ExecutionStory from a completed job.
    func reconstruct(jobId: UUID) -> ExecutionStory? {
        guard let job = jobStore.fetchJob(jobId) else {
            log.warning("Replay: job \(jobId) not found")
            return nil
        }
        let steps = jobStore.fetchSteps(jobId: jobId)
        return ExecutionStory(
            id: job.storyId,
            intent: job.intent,
            steps: steps,
            createdAt: job.createdAt,
            executionStartedAt: job.createdAt,
            executionEndedAt: job.state.isTerminal ? job.updatedAt : nil
        )
    }

    /// Reconstruct timeline entries from job steps.
    func reconstructTimeline(jobId: UUID) -> [(stepIndex: Int, step: StoryStep)] {
        let steps = jobStore.fetchSteps(jobId: jobId)
        return steps.enumerated().map { ($0, $1) }
    }

    // MARK: - Inspection

    func inspectStep(jobId: UUID, stepIndex: Int) -> StoryStep? {
        let steps = jobStore.fetchSteps(jobId: jobId)
        guard steps.indices.contains(stepIndex) else { return nil }
        return steps[stepIndex]
    }

    // MARK: - Deterministic Replay (debugging)

    /// Re-run a job with the same inputs for debugging.
    /// Creates a fresh job with a *reference* to the original jobId.
    func replay(
        jobId: UUID,
        kernel: ExecutionKernel,
        llmService: LLMService?,
        mode: ExecutionMode = .background
    ) async throws -> ExecutionJob {
        guard let original = jobStore.fetchJob(jobId) else {
            throw ReplayError.originalNotFound
        }

        let newJob = try jobStore.createJob(intent: original.intent, executionMode: mode)
        let steps = jobStore.fetchSteps(jobId: jobId)

        // Persist the same steps but with fresh IDs
        for s in steps {
            let freshStep = StoryStep(
                order: s.order,
                description: s.description,
                actionSummary: s.actionSummary,
                expectedOutput: s.expectedOutput,
                toolID: s.toolID,
                status: .pending,
                timestamp: Date()
            )
            try jobStore.appendStep(jobId: newJob.jobId, step: freshStep)
        }

        try jobStore.markJobRunning(jobId: newJob.jobId)

        Task { @MainActor in
            let orchestrator = UXOrchestrator(kernel: kernel, llmService: llmService, jobStore: jobStore)
            orchestrator.submit(intent: original.intent, existingJobId: newJob.jobId)
        }

        return newJob
    }
}

// MARK: - Errors

enum ReplayError: Error, LocalizedError {
    case originalNotFound

    var errorDescription: String? {
        switch self {
        case .originalNotFound: "Original job not found for replay"
        }
    }
}
