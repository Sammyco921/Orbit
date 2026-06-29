import Foundation
import AppKit
import UniformTypeIdentifiers
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "persistence")

@MainActor
@Observable
public final class Orchestrator {
    var conversations: [Conversation] = []
    var workspaces: [Workspace] = []
    var activeWorkspaceId: UUID?
    var activeConversationId: UUID?
    var currentPlan: Plan?
    var isProcessing = false
    public var settings = AppSettings()

    var streamingText: String = ""
    var isStreaming = false
    var streamingTask: Task<Void, Never>?
    var streamBuffer = ""
    var streamFlushTask: Task<Void, Never>?

    var timelineLog: [TimelineEntry] = []
    var useMultiAgent = false

    struct TimelineEntry: Identifiable, Sendable {
        let id: UUID
        let stepName: String
        let stepType: String
        let attempt: Int
        let outcome: String
        let detail: String

        init(stepName: String, stepType: String, attempt: Int, outcome: String, detail: String) {
            self.id = UUID()
            self.stepName = stepName
            self.stepType = stepType
            self.attempt = attempt
            self.outcome = outcome
            self.detail = detail
        }
    }

    var hasPendingCheckpoint = false
    var pendingCheckpointSummary: String = ""
    var pendingCheckpoint: ExecutionCheckpoint?

    var messages: [Message] {
        conversations.first(where: { $0.id == activeConversationId })?.messages ?? []
    }

    var toolDefinitions: [ToolDefinition] {
        runtime.toolService.toolRegistry.allDefinitions
    }

    @ObservationIgnored public var runtime: OrbitRuntime!
    @ObservationIgnored public private(set) var backgroundRuntime: OrbitBackgroundRuntime?
    public var isReady = false

    public init() {
        runtime = OrbitRuntime(settings: settings)
        let jobStore = JobStore(database: runtime.database)
        backgroundRuntime = OrbitBackgroundRuntime(
            kernel: runtime.toolService.kernel,
            eventBus: runtime.eventBus,
            permissionGate: runtime.toolService.permissionGate,
            llmService: runtime.llmService,
            jobStore: jobStore
        )
        backgroundRuntime?.uxOrchestrator.workflowEngine = runtime.workflowEngine
        backgroundRuntime?.uxOrchestrator.runtime = runtime
        // Crash recovery: requeue fresh-running jobs, fail stale ones
        let requeued = jobStore.recoverRunningJobsOnLaunch()
        if !requeued.isEmpty {
            log.notice("Recovery: requeued \(requeued.count) fresh job(s)")
        }
        syncState()
        if conversations.isEmpty {
            newConversation()
        }
        checkForPendingCheckpoint()

        Task {
            await runtime.start(settings: settings)
            isReady = true
        }
    }

    private func checkForPendingCheckpoint() {
        guard runtime.checkpointManager.checkpointCount > 0 else { return }
        if let cp = runtime.checkpointManager.loadLatest() {
            pendingCheckpoint = cp
            pendingCheckpointSummary = cp.goalDescription
            hasPendingCheckpoint = true
        }
    }

    private func syncState() {
        conversations = runtime.conversationService.conversations
        activeConversationId = runtime.conversationService.activeConversationId
        workspaces = runtime.workspaceService.workspaces
        activeWorkspaceId = runtime.workspaceService.activeWorkspaceId
    }

    // MARK: - Workspace Management

    /// Create a new workspace with the given name, icon, and optional file path.
    func createWorkspace(name: String, icon: String = "folder", path: String? = nil) {
        runtime.workspaceService.createWorkspace(name: name, icon: icon, path: path)
        syncState()
    }

    func renameWorkspace(_ id: UUID, name: String) {
        runtime.workspaceService.updateWorkspace(id, name: name)
        syncState()
    }

    func selectWorkspace(_ id: UUID) {
        runtime.workspaceService.selectWorkspace(id)
        syncState()
    }

    func deleteWorkspace(_ id: UUID) {
        runtime.workspaceService.deleteWorkspace(id)
        syncState()
    }

    func moveConversation(_ id: UUID, toWorkspaceId: UUID?) {
        runtime.conversationService.moveConversation(id, toWorkspaceId: toWorkspaceId)
        syncState()
    }

    var filteredConversations: [Conversation] {
        if let wsId = activeWorkspaceId {
            conversations.filter { $0.workspaceId == nil || $0.workspaceId == wsId }
        } else {
            conversations
        }
    }

    // MARK: - Conversation Management

    /// Create a new conversation in the active workspace and navigate to it.
    public func newConversation() {
        runtime.conversationService.createConversation(workspaceId: activeWorkspaceId)
        syncState()
    }

    /// Switch to the conversation with the given id.
    func selectConversation(_ id: UUID) {
        runtime.conversationService.selectConversation(id)
        runtime.llmService.resetProvider()
        syncState()
    }

    func renameConversation(_ id: UUID, title: String) {
        runtime.conversationService.renameConversation(id, title: title)
        syncState()
    }

    func togglePin(_ id: UUID) {
        runtime.conversationService.togglePin(id)
        syncState()
    }

    func archiveConversation(_ id: UUID) {
        runtime.conversationService.archiveConversation(id)
        syncState()
    }

    func unarchiveConversation(_ id: UUID) {
        runtime.conversationService.unarchiveConversation(id)
        syncState()
    }

    func deleteConversation(_ id: UUID) {
        runtime.conversationService.deleteConversation(id)
        syncState()
    }

    func deleteMessage(_ id: UUID) {
        runtime.conversationService.deleteMessage(id)
        syncState()
    }

    func editMessage(_ id: UUID, newContent: String) {
        guard let msgIndex = runtime.conversationService.editMessage(id, newContent: newContent) else { return }
        syncState()
        streamingTask?.cancel()
        streamingTask = Task { @MainActor in
            await processFromMessage(at: msgIndex)
            streamingTask = nil
        }
    }

    func forkConversation(at messageId: UUID) {
        runtime.conversationService.forkConversation(at: messageId)
        syncState()
    }

    func exportConversation(_ id: UUID) {
        runtime.conversationService.exportConversation(id)
    }

    func importConversation(from url: URL) {
        runtime.conversationService.importConversation(from: url)
        syncState()
    }

    var activeWorkspace: Workspace? {
        activeWorkspaceId.flatMap { id in workspaces.first(where: { $0.id == id }) }
    }

    // MARK: - LLM

    func currentProvider() -> LLMProvider {
        let config = activeConversationConfig()
        return runtime.llmService.currentProvider(config: config)
    }

    func activeConversationConfig() -> ModelConfig? {
        guard let id = activeConversationId else { return nil }
        return runtime.conversationService.conversation(for: id)?.modelConfig
    }

    func activeParameters() -> ModelParameters {
        guard let id = activeConversationId else { return ModelParameters() }
        return runtime.conversationService.conversation(for: id)?.modelConfig?.parameters ?? ModelParameters()
    }

    /// Propagate settings changes to the runtime and all services.
    func applySettings() {
        runtime.updateSettings(settings)
    }

    /// Persist all conversations to the database.
    func saveConversations() {
        runtime.conversationService.saveConversations()
    }

    var provider: LLMProvider? {
        get { nil }
        set { _ = newValue; runtime.llmService.resetProvider() }
    }

    // MARK: - Internal Helpers

    func addMessage(_ message: Message) {
        runtime.conversationService.addMessage(message)
        syncState()
    }

    func sleepUnlessCancelled(nanoseconds: UInt64) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch is CancellationError { return false } catch { return false }
    }

    func sanitizeFilename(from description: String) -> String {
        let words = description.components(separatedBy: .whitespaces).prefix(5)
        let base = words.joined(separator: "_").lowercased()
        let allowed = CharacterSet.alphanumerics.union(["_", "-"])
        return String(base.unicodeScalars.filter { allowed.contains($0) })
    }

    func userContextMessages() -> [LLMMessage] {
        messages.filter { $0.role == .user }.map { msg in
            LLMMessage(role: .user, content: msg.content, images: msg.images)
        }
    }

    // MARK: - Cancellation

    /// Cancel the currently streaming or processing response.
    func cancelResponse() {
        streamingTask?.cancel()
        streamingTask = nil
        runtime.agentRegistry.cancelAll()
        if isProcessing {
            isProcessing = false
        }
        if isStreaming {
            finalizeStreaming(with: [])
        }
    }
}
