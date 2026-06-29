import SwiftUI

struct AgentTreeView: View {
    @Environment(Orchestrator.self) var orchestrator

    private var rootAgents: [Agent] {
        orchestrator.runtime.agentRegistry.rootAgents
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rootAgents.isEmpty {
                emptyState
            } else {
                agentList
            }
        }
        .frame(minWidth: 380, minHeight: 300)
    }

    private var header: some View {
        HStack {
            Text("Agent Teams").font(.headline)
            Spacer()

            if !rootAgents.isEmpty {
                Button("Clear Completed") {
                    orchestrator.runtime.agentRegistry.clearCompleted()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button("Cancel All", systemImage: "stop") {
                    orchestrator.runtime.agentRegistry.cancelAll()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "flowchart")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Active Agents")
                .font(.title3)
            Text("Agent teams are created when you run a task in multi-agent mode.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var agentList: some View {
        List {
            ForEach(rootAgents, id: \.id) { agent in
                AgentTreeNodeView(agent: agent, depth: 0)
            }
        }
    }
}

private struct AgentTreeNodeView: View {
    let agent: Agent
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            agentHeader

            if !agent.messages.isEmpty {
                messageLog
            }

            if !agent.children.isEmpty {
                ForEach(agent.children, id: \.id) { child in
                    AgentTreeNodeView(agent: child, depth: depth + 1)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private var agentHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: agent.type.icon)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .fontWeight(.medium)
                if let goal = agent.currentGoal {
                    Text(goal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            statusBadge

            if agent.status == .running {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 4)
        .padding(.leading, CGFloat(depth) * 16)
    }

    @ViewBuilder
    private var messageLog: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(agent.messages.suffix(5), id: \.id) { msg in
                HStack(spacing: 4) {
                    Image(systemName: messageIcon(msg.type))
                        .font(.caption2)
                    Text(msg.content.prefix(120))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, CGFloat(depth) * 16 + 24)
    }

    private var statusBadge: some View {
        Text(agent.status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch agent.status {
        case .idle: return .secondary
        case .running: return .blue
        case .waitingForInput: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private func messageIcon(_ type: AgentMessageType) -> String {
        switch type {
        case .taskAssignment: return "arrow.right.circle"
        case .taskResult: return "checkmark.circle"
        case .taskFailed: return "xmark.circle"
        case .statusUpdate: return "arrow.triangle.2.circlepath"
        case .requestReview: return "eye"
        case .reviewResult: return "checkmark.seal"
        case .requestClarification: return "questionmark.circle"
        case .clarification: return "bubble.left"
        case .cancel: return "stop"
        }
    }
}
