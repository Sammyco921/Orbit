import SwiftUI

struct SidebarView: View {
    @Binding var isCollapsed: Bool
    @Binding var selectedSection: NavSection
    @Binding var showInspector: Bool

    @Environment(Orchestrator.self) private var orchestrator
    @Environment(\.uxOrchestrator) private var uxOrchestrator

    @State private var expandedProjects: Set<UUID> = []

    private let collapsedWidth: CGFloat = 48
    private let expandedWidth: CGFloat = 220

    var body: some View {
        HStack(spacing: 0) {
            collapsedRail
                .frame(width: collapsedWidth)
                .background(Color.orbitSurface)

            if !isCollapsed {
                expandedPanel
                    .frame(width: expandedWidth - collapsedWidth)
                    .background(Color.orbitSurfaceSecondary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(AnimationToken.Spring.interactive, value: isCollapsed)
        .frame(width: isCollapsed ? collapsedWidth : expandedWidth)
    }

    // MARK: - Collapsed Rail

    private var collapsedRail: some View {
        VStack(spacing: 0) {
            systemIdentity(compact: true)
                .padding(.top, Spacing.sm)

            Divider()
                .overlay(Color.orbitBorder)
                .padding(.horizontal, 8)
                .padding(.vertical, Spacing.xs)

            ForEach(NavSection.allCases, id: \.self) { section in
                navButton(section, compact: true)
            }

            Spacer()

            VStack(spacing: Spacing.xxs) {
                Button {
                    showInspector.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundStyle(showInspector ? .orbitAccent : .orbitSecondary)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .help("Toggle Inspector")

                collapseButton(compact: true)
            }
            .padding(.bottom, Spacing.sm)
        }
    }

    // MARK: - Expanded Panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            systemIdentity(compact: false)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

            Divider()
                .overlay(Color.orbitBorder)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

            actionButtons
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.sm)

            Divider()
                .overlay(Color.orbitBorder)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    projectsSection

                    Divider()
                        .overlay(Color.orbitBorder)
                        .padding(.vertical, Spacing.xs)

                    navigationSection
                }
            }

            if let orch = uxOrchestrator, orch.stateMachine.isInterruptible {
                executionControls
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
            }

            VStack(spacing: 0) {
                Divider().overlay(Color.orbitBorder)

                Button {
                    showInspector.toggle()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 13))
                        Text("Inspector")
                            .font(.orbitBodySmall)
                        Spacer()
                    }
                    .foregroundStyle(showInspector ? .orbitAccent : .orbitSecondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                }
                .buttonStyle(.plain)

                Divider().overlay(Color.orbitBorder)

                collapseButton(compact: false)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            Button {
                orchestrator.createWorkspace(name: "New Project")
                withAnimation(AnimationToken.Ease.standardOut) { expandedProjects.insert(orchestrator.activeWorkspaceId ?? UUID()) }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orbitAccent)
                    Text("New Project")
                        .font(.orbitBodySmall)
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 7)
                .background(Color.orbitAccent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.orbitAccent.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedSection = .workspace
                orchestrator.newConversation()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "plus.message")
                        .font(.system(size: 12))
                        .foregroundStyle(.orbitPrimary)
                    Text("New Chat")
                        .font(.orbitBodySmall)
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 7)
                .background(Color.orbitSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.orbitBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Projects Section

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PROJECTS")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)

            if orchestrator.workspaces.isEmpty && standaloneChats.isEmpty {
                HStack(spacing: 6) {
                    Text("No projects yet")
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitTertiary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                }
            } else {
                ForEach(orchestrator.workspaces) { workspace in
                    projectRow(workspace)
                }

                if !standaloneChats.isEmpty {
                    standaloneSection
                }
            }
        }
    }

    private var standaloneChats: [Conversation] {
        orchestrator.conversations.filter { $0.workspaceId == nil }
    }

    private var standaloneSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("QUICK CHATS")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)
                .padding(.top, 4)

            ForEach(standaloneChats.prefix(5)) { chat in
                chatRow(chat)
            }

            if standaloneChats.count > 5 {
                Text("+\(standaloneChats.count - 5) more")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 4)
            }
        }
    }

    private func projectRow(_ workspace: Workspace) -> some View {
        let isExpanded = expandedProjects.contains(workspace.id)
        let isActive = orchestrator.activeWorkspaceId == workspace.id
        let projectChats = chatsForWorkspace(workspace.id)

        return VStack(alignment: .leading, spacing: 1) {
            Button {
                if isExpanded {
                    expandedProjects.remove(workspace.id)
                } else {
                    expandedProjects.insert(workspace.id)
                }
                orchestrator.selectWorkspace(workspace.id)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.orbitTertiary)
                        .frame(width: 8)

                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? .orbitAccent : .orbitSecondary)
                        .frame(width: 14)

                    Text(workspace.name)
                        .font(.orbitBodySmall)
                        .foregroundStyle(isActive ? .orbitPrimary : .orbitSecondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(projectChats.count)")
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(isActive ? Color.orbitAccent.opacity(0.06) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            if isExpanded {
                if projectChats.isEmpty {
                    Text("No chats")
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                        .padding(.leading, 38)
                        .padding(.vertical, 4)
                } else {
                    ForEach(projectChats.prefix(10)) { chat in
                        chatRow(chat)
                            .padding(.leading, 16)
                    }
                    if projectChats.count > 10 {
                        Text("+\(projectChats.count - 10) more")
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitTertiary)
                            .padding(.leading, 38)
                            .padding(.vertical, 4)
                    }
                }

                Button {
                    selectedSection = .workspace
                    orchestrator.newConversation()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "plus")
                            .font(.system(size: 10))
                            .foregroundStyle(.orbitTertiary)
                            .frame(width: 14)
                        Text("New Chat")
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitTertiary)
                    }
                    .padding(.leading, 38)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chatRow(_ chat: Conversation) -> some View {
        let isActive = orchestrator.activeConversationId == chat.id
        return Button {
            selectedSection = .workspace
            orchestrator.selectConversation(chat.id)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "message")
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? .orbitAccent : .orbitTertiary)
                    .frame(width: 12)

                Text(chat.title)
                    .font(.orbitBodySmall)
                    .foregroundStyle(isActive ? .orbitPrimary : .orbitSecondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 5)
            .background(isActive ? Color.orbitAccent.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private func chatsForWorkspace(_ id: UUID) -> [Conversation] {
        orchestrator.conversations
            .filter { $0.workspaceId == id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Navigation Section

    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("NAVIGATION")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 4)

            ForEach(NavSection.allCases, id: \.self) { section in
                navButton(section, compact: false)
            }
        }
    }

    // MARK: - System Identity

    private func systemIdentity(compact: Bool) -> some View {
        let state = uxOrchestrator?.state ?? .idle
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "orbit")
                .font(.system(size: compact ? 18 : 20, weight: .semibold))
                .foregroundStyle(.orbitAccent)

            if !compact {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Orbit")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.orbitPrimary)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(stateColor(state))
                            .frame(width: 6, height: 6)
                        Text(stateLabel(state))
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Nav Button

    private func navButton(_ section: NavSection, compact: Bool) -> some View {
        let isActive = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            if compact {
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .orbitAccent : .orbitSecondary)
                    .frame(height: 36)
                    .frame(maxWidth: .infinity)
                    .background(isActive ? Color.orbitAccent.opacity(0.1) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: section.icon)
                        .font(.system(size: 15))
                        .foregroundStyle(isActive ? .orbitAccent : .orbitSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(section.label)
                            .font(.orbitBodySmall)
                            .foregroundStyle(isActive ? .orbitPrimary : .orbitSecondary)
                        if let subtitle = section.subtitle {
                            Text(subtitle)
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitTertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 8)
                .background(isActive ? Color.orbitAccent.opacity(0.1) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Execution Controls

    private var executionControls: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("EXECUTION")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)

            Button(role: .destructive) {
                uxOrchestrator?.cancel()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12))
                    Text("Cancel")
                        .font(.orbitBodySmall)
                    Spacer()
                }
                .foregroundStyle(.orbitError)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 8)
                .background(Color.orbitError.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Collapse Button

    private func collapseButton(compact: Bool) -> some View {
        Button {
            isCollapsed.toggle()
        } label: {
            if compact {
                Image(systemName: isCollapsed ? "sidebar.leading" : "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(.orbitTertiary)
                    .frame(height: 32)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12))
                    Text("Collapse")
                        .font(.orbitBodySmall)
                    Spacer()
                }
                .foregroundStyle(.orbitTertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
            }
        }
        .buttonStyle(.plain)
        .help("Toggle sidebar")
    }

    // MARK: - Helpers

    private func stateColor(_ state: UXState) -> Color {
        switch state {
        case .idle: .orbitSuccess
        case .interpreting, .planning, .executing: .orbitAccent
        case .failed: .orbitError
        case .completed: .orbitSuccess
        case .cancelled: .orbitWarning
        }
    }

    private func stateLabel(_ state: UXState) -> String {
        switch state {
        case .idle: OrbitVoice.Status.idle
        case .interpreting: OrbitVoice.Status.interpreting
        case .planning: OrbitVoice.Status.planning
        case .executing: OrbitVoice.Status.executing
        case .failed: OrbitVoice.Status.failed
        case .completed: OrbitVoice.Status.completed
        case .cancelled: OrbitVoice.Status.cancelled
        }
    }
}
