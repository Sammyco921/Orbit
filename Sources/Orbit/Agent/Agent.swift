import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "agent")

/// Protocol for agent events emitted to the UI
enum AgentLifecycleEvent: Sendable {
    case started(agentId: String)
    case statusChanged(agentId: String, status: AgentStatus)
    case messageSent(AgentMessage)
    case taskAssigned(AgentTask)
    case taskCompleted(taskId: UUID, result: AgentTaskResult)
    case taskFailed(taskId: UUID, error: String)
    case finished(agentId: String, result: String)
    case cancelled(agentId: String)
}

/// Base class for all agents
class Agent: Identifiable, ObservableObject {
    let id: String
    let name: String
    let type: AgentType
    let capabilities: [AgentCapability]
    @Published private(set) var status: AgentStatus = .idle
    @Published private(set) var currentGoal: String?
    @Published private(set) var output: String = ""
    @Published private(set) var error: String?

    weak var parent: Agent?
    @Published private(set) var children: [Agent] = []
    @Published private(set) var messages: [AgentMessage] = []
    @Published private(set) var tasks: [AgentTask] = []
    @Published var completedTasks: [AgentTaskResult] = []

    var onLifecycleEvent: ((AgentLifecycleEvent) -> Void)?

    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private var currentTask: Task<Void, Never>?

    init(id: String? = nil, name: String, type: AgentType, capabilities: [AgentCapability] = []) {
        self.id = id ?? "\(type.rawValue)-\(UUID().uuidString.prefix(8))"
        self.name = name
        self.type = type
        self.capabilities = capabilities
    }

    /// Start working on a goal
    func start(goal: String, context: AgentTaskContext) -> AsyncStream<String> {
        currentTask?.cancel()
        currentTask = nil
        currentGoal = goal
        status = .running
        emit(.started(agentId: id))
        emit(.statusChanged(agentId: id, status: .running))

        return AsyncStream { continuation in
            let task = Task {
                do {
                    let result = try await execute(goal: goal, context: context)
                    output = result
                    status = .completed
                    emit(.statusChanged(agentId: id, status: .completed))
                    emit(.finished(agentId: id, result: result))
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    if status == .cancelled {
                        continuation.finish()
                        return
                    }
                    self.error = error.localizedDescription
                    status = .failed
                    emit(.statusChanged(agentId: id, status: .failed))
                    continuation.finish()
                }
            }
            currentTask = task
        }
    }

    /// Subclasses override this to do actual work
    func execute(goal: String, context: AgentTaskContext) async throws -> String {
        fatalError("Subclass must implement execute")
    }

    /// Cancel the agent's work
    func cancel() {
        guard status == .running else { return }
        status = .cancelled
        currentTask?.cancel()
        currentTask = nil
        cancellationContinuation?.resume()
        cancellationContinuation = nil
        for child in children {
            child.cancel()
        }
        emit(.cancelled(agentId: id))
        emit(.statusChanged(agentId: id, status: .cancelled))
    }

    /// Send a message to this agent (from another agent)
    func receive(message: AgentMessage) {
        messages.append(message)
    }

    /// Add a child agent
    func addChild(_ agent: Agent) {
        agent.parent = self
        children.append(agent)
        agent.onLifecycleEvent = { [weak self] event in
            self?.emit(event)
        }
    }

    /// Send a message to another agent
    func send(message: AgentMessage, to agent: Agent) {
        agent.receive(message: message)
        messages.append(message)
        emit(.messageSent(message))
    }

    /// Assign a task to a child agent
    func assignTask(_ task: AgentTask, to agent: Agent) {
        tasks.append(task)
        emit(.taskAssigned(task))
        let msg = AgentMessage(from: id, to: agent.id, type: .taskAssignment, content: task.description, metadata: [
            "taskId": task.id.uuidString,
            "agentType": task.assignedAgentType.rawValue
        ])
        send(message: msg, to: agent)
    }

    func emit(_ event: AgentLifecycleEvent) {
        onLifecycleEvent?(event)
    }
}
