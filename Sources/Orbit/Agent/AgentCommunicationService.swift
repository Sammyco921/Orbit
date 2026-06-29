import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "agent-comm")

actor AgentCommunicationService {
    private var subscribers: [AgentMessageType: [String]] = [:]
    private var messageHistory: [AgentMessage] = []
    private let eventBus: EventBus?
    private var agentIds: Set<String> = []

    init(eventBus: EventBus? = nil) {
        self.eventBus = eventBus
    }

    // MARK: - Registration

    func registerAgent(id: String) {
        agentIds.insert(id)
        log.debug("Agent registered for comm: \(id)")
    }

    func unregisterAgent(id: String) {
        agentIds.remove(id)
        for (type, subs) in subscribers {
            subscribers[type] = subs.filter { $0 != id }
        }
        let dropped = pendingMessages.removeValue(forKey: id)?.count ?? 0
        if dropped > 0 {
            log.debug("Dropped \(dropped) pending messages for unregistered agent \(id)")
        }
    }

    func subscribe(agentId: String, to type: AgentMessageType) {
        if subscribers[type] == nil { subscribers[type] = [] }
        if !(subscribers[type]?.contains(agentId) ?? false) {
            subscribers[type]?.append(agentId)
        }
    }

    func unsubscribe(agentId: String, from type: AgentMessageType) {
        subscribers[type]?.removeAll { $0 == agentId }
    }

    // MARK: - Constants

    private let maxHistory = 1000
    private let maxPendingPerAgent = 100

    // MARK: - Sending

    func send(_ message: AgentMessage) {
        messageHistory.append(message)
        if messageHistory.count > maxHistory {
            messageHistory.removeFirst(messageHistory.count - maxHistory)
        }
        log.debug("AgentComm: \(message.fromAgentId) -> \(message.toAgentId ?? "*") [\(message.type.rawValue)] \(message.content.prefix(80))")

        eventBus?.publish(AgentActionEvent(
            executionId: message.fromAgentId,
            actionType: "agent_message.\(message.type.rawValue)",
            toolName: nil,
            detail: "\(message.fromAgentId) -> \(message.toAgentId ?? "broadcast"): \(message.content.prefix(100))",
            timestamp: message.timestamp
        ))

        if let toId = message.toAgentId {
            // Direct message
            notifyAgent(id: toId, message: message)
        } else {
            // Broadcast to subscribers of this message type
            for subscriberId in subscribers[message.type] ?? [] {
                notifyAgent(id: subscriberId, message: message)
            }
        }
    }

    func broadcast(_ message: AgentMessage) {
        var broadcast = AgentMessage(
            from: message.fromAgentId, to: nil,
            type: message.type, content: message.content,
            metadata: message.metadata
        )
        messageHistory.append(broadcast)
        for agentId in agentIds where agentId != message.fromAgentId {
            notifyAgent(id: agentId, message: broadcast)
        }
    }

    // MARK: - History

    func messages(for agentId: String) -> [AgentMessage] {
        messageHistory.filter { $0.fromAgentId == agentId || $0.toAgentId == agentId }
    }

    func messages(type: AgentMessageType) -> [AgentMessage] {
        messageHistory.filter { $0.type == type }
    }

    func recentMessages(limit: Int = 50) -> [AgentMessage] {
        Array(messageHistory.suffix(limit))
    }

    func clear() {
        messageHistory.removeAll()
    }

    // MARK: - Private

    private func notifyAgent(id: String, message: AgentMessage) {
        var msgs = pendingMessages[id, default: []]
        msgs.append(message)
        if msgs.count > maxPendingPerAgent {
            msgs.removeFirst(msgs.count - maxPendingPerAgent)
        }
        pendingMessages[id] = msgs
    }

    // MARK: - Polling API (for agents to pull messages)

    private var pendingMessages: [String: [AgentMessage]] = [:]

    func pending(for agentId: String) -> [AgentMessage] {
        let messages = pendingMessages[agentId] ?? []
        pendingMessages.removeValue(forKey: agentId)
        return messages
    }

    func hasPending(for agentId: String) -> Bool {
        (pendingMessages[agentId]?.isEmpty ?? true) == false
    }
}
