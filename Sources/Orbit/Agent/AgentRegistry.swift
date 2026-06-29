import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "agent-registry")

/// Registry of agent types and running agent instances
final class AgentRegistry: ObservableObject {
    @Published private(set) var agents: [String: Agent] = [:]
    @Published private(set) var rootAgents: [Agent] = []

    var onLifecycleEvent: ((AgentLifecycleEvent) -> Void)?
    var sharedMemory: SharedMemoryService?
    var communicationService: AgentCommunicationService?

    /// Register an agent
    func register(_ agent: Agent) {
        agents[agent.id] = agent
        if agent.parent == nil {
            rootAgents.append(agent)
        }
        agent.onLifecycleEvent = { [weak self] event in
            self?.onLifecycleEvent?(event)
        }
        log.notice("Registered agent: \(agent.name) (\(agent.id))")
    }

    /// Unregister an agent and its children
    func unregister(_ agent: Agent) {
        for child in agent.children {
            unregister(child)
        }
        agents.removeValue(forKey: agent.id)
        rootAgents.removeAll { $0.id == agent.id }
        log.notice("Unregistered agent: \(agent.name) (\(agent.id))")
    }

    /// Get all agents of a specific type
    func agents(of type: AgentType) -> [Agent] {
        agents.values.filter { $0.type == type }
    }

    /// Find an agent by ID
    func agent(id: String) -> Agent? {
        agents[id]
    }

    /// Create a specialized agent
    func createAgent(type: AgentType, name: String, runtime: OrbitRuntime) -> Agent {
        let agent: Agent
        switch type {
        case .planner:
            agent = PlannerAgent(name: name, runtime: runtime)
        case .executor:
            agent = AgentLoop.createForRuntime(runtime: runtime, name: name)
        case .researcher:
            agent = ResearcherAgent(name: name, runtime: runtime)
        case .reviewer:
            agent = ReviewerAgent(name: name, runtime: runtime)
        case .memoryManager:
            agent = MemoryManagerAgent(name: name, runtime: runtime)
        }
        register(agent)
        return agent
    }

    func createVisualAgent(name: String, runtime: OrbitRuntime) -> Agent {
        let agent = VisualAgent(name: name, runtime: runtime)
        register(agent)
        return agent
    }

    /// Create a team from a template
    func createTeam(template: AgentTeamTemplate, runtime: OrbitRuntime) -> Agent? {
        guard let planner = createAgent(type: .planner, name: template.name, runtime: runtime) as? PlannerAgent else {
            return nil
        }
        for agentType in template.agents where agentType != .planner {
            let child = createAgent(type: agentType, name: "\(agentType.displayName)", runtime: runtime)
            planner.addChild(child)
        }
        return planner
    }

    /// Cancel all running agents
    func cancelAll() {
        for agent in agents.values where agent.status == .running {
            agent.cancel()
        }
    }

    /// Clear completed agents
    func clearCompleted() {
        for agent in agents.values where agent.status == .completed || agent.status == .failed || agent.status == .cancelled {
            unregister(agent)
        }
    }
}
