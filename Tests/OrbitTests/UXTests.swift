import Testing
import Foundation
@testable import Orbit

// MARK: - UX State Machine

@Test func uxStateStartsIdle() {
    let sm = UXStateMachine()
    #expect(sm.state == .idle)
}

@Test func uxStateSubmitFromIdleTransitionsToInterpreting() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    #expect(sm.state == .interpreting)
}

@Test func uxStateSubmitFromCompletedTransitionsToInterpreting() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)   // idle → interpreting
    sm.transition(.intentInterpreted) // interpreting → planning
    sm.transition(.planGenerated(stepCount: 3)) // planning → executing
    sm.transition(.allStepsCompleted) // executing → completed
    #expect(sm.state == .completed)
    sm.transition(.submitIntent)
    #expect(sm.state == .interpreting)
}

@Test func uxStateInterpretedTransitionsToPlanning() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)   // idle → interpreting
    sm.transition(.intentInterpreted) // interpreting → planning
    #expect(sm.state == .planning)
}

@Test func uxStatePlanGeneratedTransitionsToExecuting() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 3))
    if case .executing(let current, let total) = sm.state {
        #expect(current == 0)
        #expect(total == 3)
    } else {
        Issue.record("Expected executing state, got \(sm.state)")
    }
}

@Test func uxStateStepCompletedAdvancesStep() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 3))
    sm.transition(.stepCompleted)
    if case .executing(let current, let total) = sm.state {
        #expect(current == 1)
        #expect(total == 3)
    } else {
        Issue.record("Expected executing state, got \(sm.state)")
    }
}

@Test func uxStateLastStepCompletedTransitionsToCompleted() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 2))
    sm.transition(.stepCompleted)
    sm.transition(.stepCompleted)
    #expect(sm.state == .completed)
}

@Test func uxStateAllStepsCompletedTransitionsToCompleted() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 5))
    sm.transition(.allStepsCompleted)
    #expect(sm.state == .completed)
}

@Test func uxStateStepFailedTransitionsToFailed() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 1))
    sm.transition(.stepFailed("Something broke"))
    #expect(sm.state == .failed)
}

@Test func uxStateCancelDuringExecutionTransitionsToCancelled() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 3))
    sm.transition(.cancel)
    #expect(sm.state == .cancelled)
}

@Test func uxStateCancelFromIdleIsNoOp() {
    var sm = UXStateMachine()
    sm.transition(.cancel)
    #expect(sm.state == .idle)
}

@Test func uxStateCancelFromCompletedIsNoOp() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 1))
    sm.transition(.allStepsCompleted)
    #expect(sm.state == .completed)
    sm.transition(.cancel)
    #expect(sm.state == .completed)
}

@Test func uxStateResetReturnsToIdle() {
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 1))
    sm.transition(.stepFailed("error"))
    #expect(sm.state == .failed)
    sm.transition(.reset)
    #expect(sm.state == .idle)
}

@Test func uxStateInvalidTransitionIsNoOp() {
    var sm = UXStateMachine()
    // submitting from interpreting is invalid
    sm.transition(.submitIntent)
    sm.transition(.submitIntent)
    #expect(sm.state == .interpreting)
    // intentInterpreted from idle is invalid
    var sm2 = UXStateMachine()
    sm2.transition(.intentInterpreted)
    #expect(sm2.state == .idle)
}

@Test func uxStateCanAcceptInputOnlyInTerminalStates() {
    let idle = UXStateMachine()
    #expect(idle.canAcceptInput)
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    #expect(!sm.canAcceptInput) // interpreting
    sm.transition(.intentInterpreted)
    #expect(!sm.canAcceptInput) // planning
    sm.transition(.planGenerated(stepCount: 1))
    #expect(!sm.canAcceptInput) // executing
    sm.transition(.allStepsCompleted)
    #expect(sm.canAcceptInput) // completed
    sm.transition(.submitIntent)
    sm.transition(.intentInterpreted)
    sm.transition(.planGenerated(stepCount: 1))
    sm.transition(.stepFailed("x"))
    #expect(sm.canAcceptInput) // failed
}

@Test func uxStateIsInterruptibleDuringActiveStates() {
    let idle = UXStateMachine()
    #expect(!idle.isInterruptible)
    var sm = UXStateMachine()
    sm.transition(.submitIntent)
    #expect(sm.isInterruptible) // interpreting
    sm.transition(.intentInterpreted)
    #expect(sm.isInterruptible) // planning
    sm.transition(.planGenerated(stepCount: 1))
    #expect(sm.isInterruptible) // executing
    sm.transition(.allStepsCompleted)
    #expect(!sm.isInterruptible) // completed
}

@Test func uxStateProgressDescription() {
    #expect(UXState.idle.progressDescription == "Ready")
    #expect(UXState.interpreting.progressDescription == "Interpreting request...")
    #expect(UXState.planning.progressDescription == "Planning...")
    #expect(UXState.executing(currentStep: 0, totalSteps: 3).progressDescription == "Executing step 1 of 3")
    #expect(UXState.completed.progressDescription == "Completed")
    #expect(UXState.failed.progressDescription == "Failed")
    #expect(UXState.cancelled.progressDescription == "Cancelled")
}

// MARK: - Story Model

@Test func executionStoryCreatedWithIntent() {
    let story = ExecutionStory(intent: "Test intent")
    #expect(story.intent == "Test intent")
    #expect(story.steps.isEmpty)
    #expect(story.result == nil)
    #expect(story.summary == nil)
}

@Test func storyBuilderCreatesFullStory() {
    var story = ExecutionStory(intent: "Build a website")
    let steps = [
        StoryStep(id: UUID(), order: 0, description: "Design", actionSummary: "Create design", expectedOutput: "Design doc", toolID: "design_tool"),
        StoryStep(id: UUID(), order: 1, description: "Develop", actionSummary: "Write code", expectedOutput: "Code", toolID: "dev_tool")
    ]
    story.steps = steps
    story.steps[0].status = .completed
    story.steps[0].output = "Designed layout"
    story.steps[1].status = .completed
    story.steps[1].output = "Website built successfully"
    story.summary = SummarySection(whatWasDone: "Built website", whyItWasDone: "User requested it", resultSummary: "Success")
    #expect(story.intent == "Build a website")
    #expect(story.steps.count == 2)
    #expect(story.result?.content == "Website built successfully")
    #expect(story.summary?.whatWasDone == "Built website")
    #expect(story.summary?.resultSummary == "Success")
}

@Test func storyStepStatusUpdate() {
    var story = ExecutionStory(intent: "Test")
    let id = UUID()
    let step = StoryStep(id: id, order: 0, description: "Testing", status: .inProgress, detail: nil, timestamp: Date())
    story.steps = [step]
    story.steps[0].status = .completed
    story.steps[0].detail = "Done"
    #expect(story.steps[0].status == .completed)
    #expect(story.steps[0].detail == "Done")
}

@Test func storyStepDisplayName() {
    #expect(StoryStepStatus.pending.displayName == "Pending")
    #expect(StoryStepStatus.inProgress.displayName == "In Progress")
    #expect(StoryStepStatus.completed.displayName == "Completed")
    #expect(StoryStepStatus.failed.displayName == "Failed")
    #expect(StoryStepStatus.timedOut.displayName == "Timed Out")
    #expect(StoryStepStatus.cancelled.displayName == "Cancelled")
}

@Test func storyStepCustomInitDefaults() {
    let step = StoryStep(id: UUID(), order: 1, description: "Test", status: .pending, detail: nil, timestamp: Date())
    #expect(step.toolInput == nil)
    #expect(step.permissionMode == nil)
    #expect(step.kernelDecision == nil)
    #expect(step.traceID == nil)
}

// MARK: - UX Orchestrator (lightweight lifecycle)

private func makeTestKernel() -> ExecutionKernel {
    let registry = ToolRegistry()
    let pm = PermissionManager()
    let gate = PermissionGate(permissionManager: pm)
    let bus = EventBus()
    let committer = EventCommitter(auditService: nil, eventBus: bus)
    return ExecutionKernel(toolRegistry: registry, permissionGate: gate, eventCommitter: committer)
}

@Test func uxOrchestratorStartsIdle() {
    let orch = UXOrchestrator(kernel: makeTestKernel())
    #expect(orch.state == .idle)
    #expect(orch.currentStory == nil)
}

@Test func uxOrchestratorSubmitTransitionsToInterpreting() {
    let orch = UXOrchestrator(kernel: makeTestKernel())
    orch.submit(intent: "Do something")
    #expect(orch.executionStartedAt != nil)
    #expect(orch.currentStory?.intent == "Do something")
}

@Test func uxOrchestratorCancelWhileIdleDoesNothing() {
    let orch = UXOrchestrator(kernel: makeTestKernel())
    orch.cancel()
    #expect(orch.state == .idle)
}

@Test func uxOrchestratorResetAfterExecution() {
    let orch = UXOrchestrator(kernel: makeTestKernel())
    orch.submit(intent: "Test")
    orch.reset()
    #expect(orch.state == .idle)
    #expect(orch.currentStory == nil)
    #expect(orch.executionStartedAt == nil)
    #expect(orch.executionEndedAt == nil)
}

@Test func uxOrchestratorOnIntentSubmittedCalledOnSubmit() {
    let orch = UXOrchestrator(kernel: makeTestKernel())
    var captured: String?
    orch.onIntentSubmitted = { captured = $0 }
    orch.submit(intent: "Hello")
    #expect(captured == "Hello")
}
