import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "visual-agent")

/// Agent that understands and interacts with the screen using Vision OCR + accessibility
final class VisualAgent: Agent {
    private let runtime: OrbitRuntime
    private let screenService: ScreenUnderstandingService
    private let actionRecorder: ActionRecorder

    init(name: String, runtime: OrbitRuntime) {
        self.runtime = runtime
        self.screenService = ScreenUnderstandingService()
        self.actionRecorder = ActionRecorder(screenService: screenService)
        super.init(
            name: name,
            type: .executor,
            capabilities: [
                AgentCapability(name: "screen_understanding", description: "Detects UI elements and text on screen using OCR"),
                AgentCapability(name: "visual_click", description: "Clicks UI elements by description"),
                AgentCapability(name: "visual_type", description: "Types text into fields by description"),
                AgentCapability(name: "form_filling", description: "Detects and fills form fields"),
                AgentCapability(name: "action_recording", description: "Records and replays visual action sequences")
            ]
        )
    }

    override func execute(goal: String, context: AgentTaskContext) async throws -> String {
        let provider = runtime.llmService.currentProvider()
        let prompt = buildPrompt(goal: goal, context: context)

        // Describe the current screen first
        let snapshot = try? await screenService.captureCurrentScreen()
        let screenDescription = snapshot.map { screenService.describeScreen($0) } ?? "Unable to capture screen."

        let fullPrompt = """
        \(prompt)

        Current screen state:
        \(screenDescription)

        Based on the screen state above and the user's goal, determine what actions to perform.
        Respond with instructions for the next action only.
        """

        let messages = [LLMMessage(role: .user, content: fullPrompt)]
        return try await provider.complete(messages: messages, parameters: .init(temperature: 0.3, maxTokens: 500))
    }

    /// Perform a screen capture and describe what's visible
    func captureAndDescribe() async throws -> String {
        let snapshot = try await screenService.captureCurrentScreen()
        return screenService.describeScreen(snapshot)
    }

    /// Start a visual action recording session
    func startRecording() {
        actionRecorder.startRecording()
    }

    /// Stop recording and save
    func stopRecording(name: String) throws -> ActionRecording {
        let recording = actionRecorder.stopRecording(name: name)
        try actionRecorder.saveRecording(recording)
        return recording
    }

    /// Replay a saved recording
    func replayRecording(_ recording: ActionRecording) async throws {
        try await actionRecorder.replay(recording)
    }

    /// List saved recordings
    func listRecordings() throws -> [ActionRecording] {
        try actionRecorder.loadRecordings()
    }

    // MARK: - Private

    private func buildPrompt(goal: String, context: AgentTaskContext) -> String {
        """
        You are a visual agent. Your goal is: \(goal)

        You can see what's on the user's screen. Analyze the screen state and determine the best action.

        Available actions:
        1. Click an element by describing it (e.g., "Click the submit button")
        2. Type text into a field (e.g., "Type 'hello' into the search box")
        3. Fill a form with values
        4. Describe what you see
        5. Record a sequence of actions

        Additional context: \(context.additionalInstructions ?? "None")
        """
    }
}
