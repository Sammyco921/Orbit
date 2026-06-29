import Testing
import Foundation
@testable import Orbit

struct AgentRegistryTests {

    @Test func registerAndUnregisterAgent() {
        let registry = AgentRegistry()
        let agent = TestAgent(name: "Test", type: .planner)

        registry.register(agent)
        #expect(registry.agents[agent.id] != nil)
        #expect(registry.rootAgents.contains { $0.id == agent.id })

        registry.unregister(agent)
        #expect(registry.agents[agent.id] == nil)
        #expect(!registry.rootAgents.contains { $0.id == agent.id })
    }

    @Test func agentsOfType() {
        let registry = AgentRegistry()
        let a1 = TestAgent(name: "P1", type: .planner)
        let a2 = TestAgent(name: "P2", type: .planner)
        let a3 = TestAgent(name: "E1", type: .executor)
        registry.register(a1)
        registry.register(a2)
        registry.register(a3)
        #expect(registry.agents(of: .planner).count == 2)
        #expect(registry.agents(of: .executor).count == 1)
        #expect(registry.agents(of: .researcher).isEmpty)
    }

    @Test func agentByID() {
        let registry = AgentRegistry()
        let agent = TestAgent(name: "Review", type: .reviewer)
        registry.register(agent)
        let found = registry.agent(id: agent.id)
        #expect(found?.id == agent.id)
        #expect(registry.agent(id: "nonexistent") == nil)
    }

    @Test func childrenAreNotRootAgents() {
        let registry = AgentRegistry()
        let parent = TestAgent(name: "Parent", type: .planner)
        let child = TestAgent(name: "Child", type: .executor)
        parent.addChild(child)
        registry.register(parent)
        #expect(registry.rootAgents.count == 1)
        #expect(registry.rootAgents.first?.id == parent.id)
    }

    @Test func unregisterRemovesChildren() {
        let registry = AgentRegistry()
        let parent = TestAgent(name: "Parent", type: .executor)
        let child = TestAgent(name: "Child", type: .researcher)
        parent.addChild(child)
        registry.register(parent)
        registry.register(child)
        #expect(registry.agents.count == 2)

        registry.unregister(parent)
        #expect(registry.agents.isEmpty)
    }
}

// MARK: - Test Agent

private class TestAgent: Agent {
    init(name: String, type: AgentType) {
        super.init(name: name, type: type)
    }
}
