import Foundation
import os

// MARK: - JobScheduler

/// The single authority for moving jobs into the RUNNING state.
/// Owns the active queue, enforces concurrency limits, and provides
/// the menu bar / UI with a clean state-machine interface.
///
/// State machine (this class enforces):
///   Queued → Running → Terminal (Completed / Failed / Cancelled)
///                    ↘ Paused ↗
///
/// Only `popAndRunNext()` transitions a job to RUNNING.
/// External code (Orchestrator, BackgroundExecutionEngine) must call
/// `popAndRunNext()` or `pauseJob()` / `resumeJob()` — never mutate job states directly.
@MainActor
final class JobScheduler {
    let store: JobStore
    let concurrencyLimit: Int

    /// Maximum pause duration after which a PAUSED job is auto-cancelled.
    /// `nil` means no auto-cancel.
    let maxPauseDuration: TimeInterval? = 600 // 10 minutes

    private let log = Logger(subsystem: "Orbit", category: "scheduler")

    init(store: JobStore, concurrencyLimit: Int = 1) {
        self.store = store
        self.concurrencyLimit = concurrencyLimit
    }

    // MARK: - Submit

    /// Submit a new intent as a queued job. Returns the created `ExecutionJob`.
    @discardableResult
    func submitIntent(_ intent: String, executionMode: ExecutionMode = .background) -> ExecutionJob? {
        do {
            let job = try store.createJob(intent: intent, executionMode: executionMode)
            try store.markJobQueued(jobId: job.jobId)
            log.notice("Submitted job \(job.jobId) — \(intent.prefix(60))")
            return job
        } catch {
            log.error("Failed to submit job: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Queue Management

    var queueCount: Int {
        store.fetchQueuedJobs().count
    }

    var activeCount: Int {
        store.fetchRunningJob() != nil ? 1 : 0
    }

    var pausedCount: Int {
        store.fetchPausedJobs().count
    }

    /// Whether a new job can be started right now.
    var canRunNext: Bool {
        activeCount < concurrencyLimit && queueCount > 0
    }

    /// Pop the next queued job and transition it to RUNNING.
    /// Returns the job if one was promoted, nil otherwise.
    @discardableResult
    func popAndRunNext() -> ExecutionJob? {
        guard canRunNext else { return nil }
        guard let job = store.popNextQueuedJob() else { return nil }
        log.notice("Promoted job \(job.jobId) to RUNNING")
        return job
    }

    /// Get the currently running job, if any.
    var currentRunningJob: ExecutionJob? {
        store.fetchRunningJob()
    }

    /// All active (non-terminal) jobs, ordered by queue position.
    var allActiveJobs: [ExecutionJob] {
        store.fetchAllActiveJobs()
    }

    /// Queued jobs in order.
    var queuedJobs: [ExecutionJob] {
        store.fetchQueuedJobs()
    }

    // MARK: - Pause / Resume

    func pauseJob(jobId: UUID) {
        guard store.fetchJob(jobId)?.state == .running else {
            log.warning("Cannot pause job \(jobId): not RUNNING")
            return
        }
        try? store.markJobPaused(jobId: jobId)
        log.notice("Paused job \(jobId)")
    }

    @discardableResult
    func resumeJob(jobId: UUID) -> Bool {
        guard store.fetchJob(jobId)?.state == .paused else {
            log.warning("Cannot resume job \(jobId): not PAUSED")
            return false
        }
        try? store.markJobRunning(jobId: jobId)
        log.notice("Resumed job \(jobId)")
        return true
    }

    // MARK: - Cancel

    func cancelJob(jobId: UUID) {
        guard let job = store.fetchJob(jobId), !job.state.isTerminal else { return }
        try? store.markJobCancelled(jobId: jobId)
        log.notice("Cancelled job \(jobId)")
    }

    // MARK: - Heartbeat (called by the engine)

    func heartbeat(jobId: UUID) {
        try? store.updateHeartbeat(jobId: jobId)
    }

    // MARK: - Cleanup

    func cancelAllQueued() {
        for job in store.fetchQueuedJobs() {
            try? store.markJobCancelled(jobId: job.jobId)
        }
    }

    // MARK: - Status

    var status: SchedulerStatus {
        if let running = currentRunningJob {
            return .running(running)
        }
        if pausedCount > 0 {
            return .paused(pausedCount)
        }
        if queueCount > 0 {
            return .queued(queueCount)
        }
        return .idle
    }
}

// MARK: - Scheduler Status

enum SchedulerStatus: Equatable {
    case idle
    case queued(Int)
    case running(ExecutionJob)
    case paused(Int)
    case failed(ExecutionJob?)

    static func == (lhs: SchedulerStatus, rhs: SchedulerStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): true
        case (.queued(let a), .queued(let b)): a == b
        case (.running(let a), .running(let b)): a.jobId == b.jobId
        case (.paused(let a), .paused(let b)): a == b
        case (.failed(let a), .failed(let b)): a?.jobId == b?.jobId
        default: false
        }
    }
}
