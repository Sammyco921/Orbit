import SwiftUI

// MARK: - Empty State Engine

/// Unified empty state system. Every surface must have an intentional empty state.
///
/// Rules:
/// - Each empty state must include: section identity, example action, one-click entry point
/// - Never show generic text or placeholders
/// - Must use OrbitVoice for all user-facing strings
enum EmptyStateCase: String, CaseIterable, Sendable {
    case workspace
    case history
    case artifacts
    case jobs
    case agents
    case integrations
    case knowledgeBases
    case goals
    case plugins
    case workflows
    case modelConfig
    case activity
    case executionData
    case memories
    case globalMemories
    case userFacts
    case tools

    // MARK: - Identity

    var title: String {
        switch self {
        case .workspace:      OrbitVoice.Empty.noWorkspaces
        case .history:        OrbitVoice.Empty.noExecutions
        case .artifacts:      OrbitVoice.Empty.noArtifacts
        case .jobs:           OrbitVoice.Empty.noJobs
        case .agents:         OrbitVoice.Empty.noAgents
        case .integrations:   OrbitVoice.Empty.noIntegrations
        case .knowledgeBases: OrbitVoice.Empty.noKnowledgeBases
        case .goals:          OrbitVoice.Empty.noGoals
        case .plugins:        OrbitVoice.Empty.noPlugins
        case .workflows:      OrbitVoice.Empty.noWorkflows
        case .modelConfig:    OrbitVoice.Empty.noModelConfigured
        case .activity:       OrbitVoice.Empty.noActivity
        case .executionData:  OrbitVoice.Empty.noExecutionData
        case .memories:       "No conversation memories yet"
        case .globalMemories: "No global memories yet"
        case .userFacts:      "No user facts extracted yet"
        case .tools:          "No tools match your search"
        }
    }

    var description: String {
        switch self {
        case .workspace:      OrbitVoice.Empty.noWorkspacesDescription
        case .history:        OrbitVoice.Empty.noExecutionsDescription
        case .artifacts:      OrbitVoice.Empty.noArtifactsDescription
        case .jobs:           OrbitVoice.Empty.noJobsDescription
        case .agents:         OrbitVoice.Empty.noAgentsDescription
        case .integrations:   OrbitVoice.Empty.noIntegrationsDescription
        case .knowledgeBases: OrbitVoice.Empty.noKnowledgeBasesDescription
        case .goals:          OrbitVoice.Empty.noGoalsAction
        case .plugins:        OrbitVoice.Empty.noPluginsDescription
        case .workflows:      OrbitVoice.Empty.noWorkflowsAction
        case .modelConfig:    OrbitVoice.Empty.noModelConfiguredDescription
        case .activity:       "Steps and tool calls will appear here during execution."
        case .executionData:  "Start an execution to see debug information."
        case .memories:       "Conversation memories are created automatically as you interact."
        case .globalMemories: "Global memories are shared across all conversations."
        case .userFacts:      "User facts are extracted automatically from interactions."
        case .tools:          "Try a different search term or filter."
        }
    }

    var systemImage: String {
        switch self {
        case .workspace:      "square.grid.2x2"
        case .history:        "clock.arrow.circlepath"
        case .artifacts:      "doc"
        case .jobs:           "list.bullet.rectangle"
        case .agents:         "person.2"
        case .integrations:   "link"
        case .knowledgeBases: "book"
        case .goals:          "target"
        case .plugins:        "puzzlepiece"
        case .workflows:      "flowchart"
        case .modelConfig:    "network.slash"
        case .activity:       "tray"
        case .executionData:  "ant"
        case .memories:       "brain"
        case .globalMemories: "globe"
        case .userFacts:      "person.text.rectangle"
        case .tools:          "magnifyingglass"
        }
    }

    /// The primary action label for one-click entry.
    var actionLabel: String? {
        switch self {
        case .workspace:      OrbitVoice.Empty.noWorkspacesAction
        case .history:        OrbitVoice.Empty.noExecutionsAction
        case .jobs:           OrbitVoice.Empty.noJobsAction
        case .plugins:        "Browse Registry"
        case .modelConfig:    OrbitVoice.Empty.setupModel
        case .goals:          OrbitVoice.Empty.noGoalsAction
        case .workflows:      OrbitVoice.Empty.noWorkflowsAction
        default: nil
        }
    }
}

// MARK: - Empty State View

struct UnifiedEmptyState: View {
    let `case`: EmptyStateCase
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: `case`.systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.orbitTertiary)

            Text(`case`.title)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitPrimary)

            Text(`case`.description)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .multilineTextAlignment(.center)

            if let label = `case`.actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.top, Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
