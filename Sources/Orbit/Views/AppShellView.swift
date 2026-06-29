import SwiftUI

// MARK: - Environment keys

private struct UXOrchestratorKey: EnvironmentKey {
    static let defaultValue: UXOrchestrator? = nil
}

extension EnvironmentValues {
    var uxOrchestrator: UXOrchestrator? {
        get { self[UXOrchestratorKey.self] }
        set { self[UXOrchestratorKey.self] = newValue }
    }
}

struct NavigationAction {
    let navigate: (NavSection) -> Void
}

private struct NavigateToSectionKey: EnvironmentKey {
    static let defaultValue: NavigationAction? = nil
}

extension EnvironmentValues {
    var navigateToSection: NavigationAction? {
        get { self[NavigateToSectionKey.self] }
        set { self[NavigateToSectionKey.self] = newValue }
    }
}

private struct SuggestedIntentKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var suggestedIntent: String? {
        get { self[SuggestedIntentKey.self] }
        set { self[SuggestedIntentKey.self] = newValue }
    }
}

// MARK: - App Shell (3-pane layout)

public struct AppShellView: View {
    @Environment(Orchestrator.self) private var orchestrator

    @State private var sidebarCollapsed = false
    @State private var selectedSection: NavSection = .workspace
    @State private var showInspector = false
    @State private var showOnboarding = false
    @State private var intentSuggestion: String?

    public init() {}

    public var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    isCollapsed: $sidebarCollapsed,
                    selectedSection: $selectedSection,
                    showInspector: $showInspector
                )

                centerContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector {
                    InspectorPanelView()
                        .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .background(Color.orbitBackground)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: showInspector)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: sidebarCollapsed)
            .environment(\.sidebarCollapsed, sidebarCollapsed)
            .environment(\.uxOrchestrator, orchestrator.backgroundRuntime?.uxOrchestrator)
            .environment(\.navigateToSection, NavigationAction(navigate: { section in
                selectedSection = section
            }))
            .environment(\.suggestedIntent, intentSuggestion)
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
                selectedSection = .settings
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToHistory)) { _ in
                selectedSection = .history
                NSApp.activate(ignoringOtherApps: true)
            }

            if showOnboarding {
                OnboardingFlowView {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showOnboarding = false
                        intentSuggestion = "List the files in this project"
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .onAppear {
            setupUICallbacks()
            if !orchestrator.settings.hasCompletedOnboarding {
                withAnimation(.easeOut(duration: 0.3)) {
                    showOnboarding = true
                }
            }
        }
    }

    private func setupUICallbacks() {
        guard let ux = orchestrator.backgroundRuntime?.uxOrchestrator else { return }
        ux.onIntentSubmitted = { [weak orchestrator] intent in
            orchestrator?.addMessage(Message(role: .user, content: intent))
        }
        ux.onAssistantResponse = { [weak orchestrator] response in
            orchestrator?.addMessage(Message(role: .assistant, content: response))
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch selectedSection {
        case .workspace:
            ExecutionWorkspaceView()
        case .history:
            ExecutionHistoryView()
        case .agents:
            if let runtime = orchestrator.runtime {
                AgentsHubView(store: runtime.workflowStore, engine: runtime.workflowEngine, registry: runtime.agentRegistry)
            } else {
                OrbitEmptyState(icon: "brain.head.profile", title: "Agents", description: "Agent system not available.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.orbitBackground)
            }
        case .files:
            ArtifactManagerView()
        case .integrations:
            if let runtime = orchestrator.runtime {
                IntegrationsListView(hub: runtime.integrationHub)
            } else {
                OrbitEmptyState(icon: "link", title: "Integrations", description: "Integration hub not available.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.orbitBackground)
            }
        case .plugins:
            PluginBrowserView()
        case .settings:
            SettingsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Nav Section

enum NavSection: String, CaseIterable {
    case workspace
    case history
    case agents
    case files
    case integrations
    case plugins
    case settings

    var icon: String {
        switch self {
        case .workspace: "message"
        case .history: "clock.arrow.circlepath"
        case .agents: "brain.head.profile"
        case .files: "doc.text"
        case .integrations: "link"
        case .plugins: "puzzlepiece.extension"
        case .settings: "gearshape"
        }
    }

    var label: String {
        switch self {
        case .workspace: "Workspace"
        case .history: "History"
        case .agents: "Agents"
        case .files: "File Library"
        case .integrations: "Integrations"
        case .plugins: "Plugins"
        case .settings: "Settings"
        }
    }

    var subtitle: String? {
        switch self {
        case .workspace: "Execute tasks in real time"
        case .history: "Review past executions and outcomes"
        case .agents: "Automate with multi-agent workflows"
        case .files: "Browse generated artifacts and files"
        case .integrations: "Connect external services"
        case .plugins: "Extend Orbit with plugins"
        case .settings: "Configure models and preferences"
        }
    }
}

// MARK: - Environment key

private struct SidebarCollapsedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarCollapsed: Bool {
        get { self[SidebarCollapsedKey.self] }
        set { self[SidebarCollapsedKey.self] = newValue }
    }
}
