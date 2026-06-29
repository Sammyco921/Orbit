import Foundation
import os

// MARK: - Background Execution Engine

/// The background execution engine runs jobs from the scheduler's queue
/// outside the UI lifecycle. It survives app restart and window close.
///
/// Lifecycle:
/// 1. Engine starts (`start()`), begins polling scheduler for work
/// 2. Scheduler pops next QUEUED job → RUNNING
/// 3. Engine creates a fresh UXOrchestrator and runs the job
/// 4. On completion, engine loops back to step 2
/// 5. On app restart, engine recovers RUNNING/QUEUED jobs from the store
///
/// The engine is ``@MainActor`` because UXOrchestrator requires main-actor access
/// for its `@Observable` bindings. This is fine since execution is async and
/// cooperative; the engine never blocks the main thread.
@MainActor
final class BackgroundExecutionEngine {
    let scheduler: JobScheduler
    private let kernel: ExecutionKernel
    private let llmService: LLMService?
    private let permissionGate: PermissionGate
    private let eventBus: EventBus

    private var engineTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var currentOrchestrator: UXOrchestrator?
    private var isRunning = false

    private let log = Logger(subsystem: "Orbit", category: "engine")

    init(
        scheduler: JobScheduler,
        kernel: ExecutionKernel,
        llmService: LLMService?,
        permissionGate: PermissionGate,
        eventBus: EventBus
    ) {
        self.scheduler = scheduler
        self.kernel = kernel
        self.llmService = llmService
        self.permissionGate = permissionGate
        self.eventBus = eventBus
    }

    /// Start the engine loop. Safe to call multiple times (only one loop runs).
    func start() {
        guard engineTask == nil else { return }
        log.notice("Engine starting")
        engineTask = Task { @MainActor in
            await runLoop()
        }
    }

    /// Gracefully stop the engine, cancelling any in-flight job.
    func stop() {
        log.notice("Engine stopping")
        engineTask?.cancel()
        engineTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        currentOrchestrator?.cancel()
        currentOrchestrator = nil
        isRunning = false
    }

    /// Whether the engine is currently idle (no active or queued work).
    var isIdle: Bool {
        scheduler.currentRunningJob == nil && scheduler.queueCount == 0 && scheduler.pausedCount == 0
    }

    /// The latest scheduler status, computed synchronously.
    var status: SchedulerStatus {
        scheduler.status
    }

    // MARK: - Run Loop

    private func runLoop() async {
        isRunning = true
        defer {
            isRunning = false
            log.notice("Engine loop ended")
        }

        while !Task.isCancelled {
            // 1. Check for a running job (e.g. from resume after pause)
            if let running = scheduler.currentRunningJob {
                await executeJob(running)
                continue
            }

            // 2. Try to pop next queued job
            if let job = scheduler.popAndRunNext() {
                await executeJob(job)
                continue
            }

            // 3. Nothing to do — idle
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    // MARK: - Execute a Single Job

    private func executeJob(_ job: ExecutionJob) async {
        log.notice("Engine executing job \(job.jobId) — \(job.intent.prefix(60))")

        let orchestrator = UXOrchestrator(
            kernel: kernel,
            llmService: llmService,
            jobStore: scheduler.store
        )
        currentOrchestrator = orchestrator

        // Start heartbeats
        startHeartbeat(for: job.jobId)

        // Use a continuation to wait for completion
        await withCheckedContinuation { continuation in
            orchestrator.onExecutionFinished = { [weak self] _ in
                self?.log.notice("Engine finished job \(job.jobId)")
                self?.heartbeatTask?.cancel()
                self?.heartbeatTask = nil
                self?.currentOrchestrator = nil
                continuation.resume()
            }

            // Submit the job using existingJobId so the orchestrator reuses
            // the persisted entry rather than creating a duplicate.
            orchestrator.submit(intent: job.intent, existingJobId: job.jobId)
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(for jobId: UUID) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s
                self?.scheduler.heartbeat(jobId: jobId)
            }
        }
    }
}
