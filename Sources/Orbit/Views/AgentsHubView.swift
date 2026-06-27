import SwiftUI

struct AgentsHubView: View {
    let store: WorkflowStore
    let engine: WorkflowEngine
    let registry: AgentRegistry

    @State private var selectedTab: Tab = .agents

    enum Tab: String, CaseIterable {
        case agents
        case workflows

        var label: String {
            switch self {
            case .agents: "Agents"
            case .workflows: "Workflows"
            }
        }

        var icon: String {
            switch self {
            case .agents: "brain.head.profile"
            case .workflows: "arrow.triangle.branch"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.orbitBorder)
            tabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitBackground)
    }

    private var header: some View {
        HStack {
            Text("Agents & Workflows")
                .font(.orbitHeadline)
                .foregroundStyle(.orbitPrimary)
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.orbitBackground)
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.label)
                            .font(.orbitBodySmall)
                    }
                    .foregroundStyle(selectedTab == tab ? .orbitPrimary : .orbitSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.orbitSurface : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.orbitSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .agents:
            AgentTreeView()
        case .workflows:
            WorkflowListView(store: store, engine: engine)
        }
    }
}
