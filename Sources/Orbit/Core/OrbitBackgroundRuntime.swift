import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "background")

@MainActor
@Observable
public final class OrbitBackgroundRuntime {
    // MARK: - Owned execution systems

    private(set) var uxOrchestrator: UXOrchestrator
    private(set) var kernel: ExecutionKernel
    private(set) var eventBus: EventBus
    private(set) var permissionGate: PermissionGate
    private(set) var llmService: LLMService?
    private(set) var jobStore: JobStore
    private(set) var replayEngine: ExecutionReplayEngine
    private(set) var scheduler: JobScheduler
    private(set) var backgroundEngine: BackgroundExecutionEngine

    // MARK: - State

    private(set) var isRunning = false
    private var lifecycleTask: Task<Void, Never>?

    init(
        kernel: ExecutionKernel,
        eventBus: EventBus,
        permissionGate: PermissionGate,
        llmService: LLMService?,
        jobStore: JobStore
    ) {
        self.kernel = kernel
        self.eventBus = eventBus
        self.permissionGate = permissionGate
        self.llmService = llmService
        self.jobStore = jobStore
        self.replayEngine = ExecutionReplayEngine(jobStore: jobStore)
        let scheduler = JobScheduler(store: jobStore)
        self.scheduler = scheduler
        let engine = BackgroundExecutionEngine(
            scheduler: scheduler,
            kernel: kernel,
            llmService: llmService,
            permissionGate: permissionGate,
            eventBus: eventBus
        )
        self.backgroundEngine = engine
        uxOrchestrator = UXOrchestrator(kernel: kernel, llmService: llmService, jobStore: jobStore)

        // Recover jobs that were running when the app last crashed
        let requeued = jobStore.recoverRunningJobsOnLaunch()
        if !requeued.isEmpty {
            log.notice("Requeued \(requeued.count) jobs on launch")
        }

        backgroundEngine.start()
        setupCallbacks()
        isRunning = true
        log.notice("Background runtime started")
    }

    // MARK: - Observable State

    var state: UXState { uxOrchestrator.state }
    var currentStory: ExecutionStory? { uxOrchestrator.currentStory }
    var lastStory: ExecutionStory? { uxOrchestrator.lastStory }

    /// Human-readable status for menu bar display.
    /// Combines interactive UX state and background scheduler state.
    var menuBarStatus: MenuBarStatus {
        guard isRunning else { return .connecting }
        let schedulerStatus = scheduler.status
        switch schedulerStatus {
        case .idle:
            // No background jobs; fall through to interactive UX state
            switch state {
            case .idle, .completed, .cancelled: return .idle
            case .interpreting, .planning, .executing, .awaitingConfirmation: return .running
            case .failed: return .failed
            }
        case .queued(let count):
            return .queued(count)
        case .running:
            return .running
        case .paused(let count):
            return .paused(count)
        case .failed:
            return .failed
        }
    }

    /// Current step progress for live preview
    var stepProgress: String? {
        guard case .executing(let current, let total) = state else { return nil }
        return "Step \(current + 1) of \(total)"
    }

    // MARK: - Lifecycle

    func submit(intent: String) {
        uxOrchestrator.submit(intent: intent)
    }

    /// Submit a job for background / scheduled execution via the JobScheduler.
    func submitBackground(intent: String) {
        scheduler.submitIntent(intent, executionMode: .background)
    }

    func cancel() {
        uxOrchestrator.cancel()
    }

    func reset() {
        uxOrchestrator.reset()
    }

    func shutDown() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        backgroundEngine.stop()
        uxOrchestrator.reset()
        isRunning = false
        log.notice("Background runtime shut down")
    }

    // MARK: - Background Job Control

    func cancelJob(jobId: UUID) {
        scheduler.cancelJob(jobId: jobId)
    }

    func pauseJob(jobId: UUID) {
        scheduler.pauseJob(jobId: jobId)
    }

    func resumeJob(jobId: UUID) -> Bool {
        scheduler.resumeJob(jobId: jobId)
    }

    // MARK: - Callbacks

    private func setupCallbacks() {
        uxOrchestrator.onStoryComplete = { [weak self] story in
            guard let self else { return }
            log.notice("Story completed: \(story.intent.prefix(60))")
        }

        uxOrchestrator.onExecutionRejected = { [weak self] in
            guard let self else { return }
            log.notice("Execution rejected — duplicate submission prevented")
        }
    }
}

// MARK: - Menu Bar Status

enum MenuBarStatus: Sendable, Equatable {
    case idle
    case running
    case queued(Int)
    case paused(Int)
    case failed
    case connecting

    var iconName: String {
        switch self {
        case .idle: "orbit"
        case .running: "orbit"
        case .queued: "clock"
        case .paused: "pause.circle"
        case .failed: "exclamationmark.circle"
        case .connecting: "circle.dashed"
        }
    }

    var tint: (red: Double, green: Double, blue: Double) {
        switch self {
        case .idle: (0.18, 0.90, 0.62)      // green
        case .running: (1.0, 0.80, 0.40)     // yellow
        case .queued: (0.25, 0.60, 1.0)      // blue
        case .paused: (0.85, 0.65, 0.20)     // orange
        case .failed: (1.0, 0.36, 0.36)      // red
        case .connecting: (0.54, 0.58, 0.65) // gray
        }
    }
}
