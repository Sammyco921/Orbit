import SwiftUI

struct ExecutionWorkspaceView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @Environment(\.uxOrchestrator) private var uxOrchestrator
    @Environment(\.suggestedIntent) private var suggestedIntent
    @State private var composerText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(Color.orbitBackground)

            Divider().overlay(Color.orbitBorder)

            TimelineView(prefillSuggestion: $composerText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            inputArea
        }
        .background(Color.orbitBackground)
        .onChange(of: suggestedIntent) { _, newValue in
            if let intent = newValue {
                composerText = intent
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let hasContext = orchestrator.activeConversationId != nil
        let conversationName = activeConversationTitle
        let workspaceName = orchestrator.activeWorkspace?.name

        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Workspace")
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitSecondary)
                    if let ws = workspaceName {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.orbitTertiary)
                        Text(ws)
                            .font(.orbitBodySmall)
                            .foregroundStyle(.orbitSecondary)
                    }
                }

                Text(hasContext ? conversationName : "Execution Workspace")
                    .font(.orbitHeadline)
                    .foregroundStyle(.orbitPrimary)
            }

            Spacer()

            if let orch = uxOrchestrator, orch.state != .idle {
                stateBadge(orch.state)
            }

            if let config = orchestrator.activeConversationConfig(), !config.model.isEmpty {
                modelBadge(config.model)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    private var activeConversationTitle: String {
        guard let id = orchestrator.activeConversationId,
              let conv = orchestrator.conversations.first(where: { $0.id == id })
        else { return "Execution Workspace" }
        return conv.title
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.orbitBorder)

            HStack(spacing: Spacing.sm) {
                InputBarView(text: $composerText)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.orbitSurface)
    }

    // MARK: - Badges

    private func stateBadge(_ state: UXState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 6, height: 6)
            Text(state.progressDescription)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(Color.orbitSurface)
        .clipShape(Capsule())
    }

    private func modelBadge(_ model: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundStyle(.orbitSecondary)
            Text(model)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 2)
        .background(Color.orbitSurface)
        .clipShape(Capsule())
    }

    private func stateColor(_ state: UXState) -> Color {
        switch state {
        case .idle: .orbitSuccess
        case .interpreting, .planning, .executing: .orbitAccent
        case .failed: .orbitError
        case .completed: .orbitSuccess
        case .cancelled: .orbitWarning
        }
    }
}
