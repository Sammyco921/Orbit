import SwiftUI

struct ExecutionWorkspaceView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @Environment(\.uxOrchestrator) private var uxOrchestrator
    @Environment(\.suggestedIntent) private var suggestedIntent
    @State private var composerText = ""
    @State private var showQuickActionBar = false
    @State private var showConversationSearch = false
    @State private var memoryUsageString: String = MemoryUsage.current
    private let memoryUpdate = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(Color.orbitBackground)

            Divider().overlay(Color.orbitBorder)

            TimelineView(prefillSuggestion: $composerText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar

            inputArea
        }
        .background(Color.orbitBackground)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .onChange(of: suggestedIntent) { _, newValue in
            if let intent = newValue {
                composerText = intent
            }
        }
        .sheet(item: approvalRequest) { request in
            ApprovalSheetView(request: request) { response in
                PendingApproval.shared.respond(response)
            }
        }
        .overlay {
            if showQuickActionBar {
                QuickActionBarView(
                    isPresented: $showQuickActionBar,
                    orchestrator: orchestrator,
                    uxOrchestrator: uxOrchestrator
                )
            }
            if showConversationSearch {
                ConversationSearchView(
                    isPresented: $showConversationSearch,
                    orchestrator: orchestrator
                )
            }
        }
        .background {
            Button("Quick Actions") { showQuickActionBar.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            Button("Search Conversations") { showConversationSearch.toggle() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .opacity(0)
                .frame(width: 0, height: 0)
        }
    }

    private var approvalRequest: Binding<ToolApprovalRequest?> {
        Binding(
            get: { PendingApproval.shared.pendingRequest },
            set: { if $0 == nil { PendingApproval.shared.cancel() } }
        )
    }

    // MARK: - Header

    private var header: some View {
        let hasContext = orchestrator.activeConversationId != nil
        let conversationName = activeConversationTitle

        return HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(workspaceBreadcrumb)
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitSecondary)
                    workspaceContextInfo
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

    private var workspaceBreadcrumb: String {
        let ws = orchestrator.activeWorkspace?.name ?? "Workspace"
        return ws
    }

    @ViewBuilder
    private var workspaceContextInfo: some View {
        if let ws = orchestrator.activeWorkspace, let path = ws.path {
            let branch = gitBranch(for: path)
            if let b = branch {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8))
                        .foregroundStyle(.orbitTertiary)
                    Text(b)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                }
            }
        }
    }

    private func gitBranch(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let headURL = url.appendingPathComponent(".git/HEAD")
        guard let data = try? String(contentsOf: headURL, encoding: .utf8) else { return nil }
        let prefix = "ref: refs/heads/"
        if data.hasPrefix(prefix) {
            return data.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSURL.self) { item, _ in
            guard let url = item as? URL else { return }
            DispatchQueue.main.async {
                self.composerText = self.intent(for: url)
            }
        }
        return true
    }

    private func intent(for url: URL) -> String {
        let path = url.path
        switch url.pathExtension.lowercased() {
        case "swift": return "Analyze this Swift file: \(path)"
        case "py": return "Analyze this Python file: \(path)"
        case "js", "ts", "jsx", "tsx": return "Analyze this JavaScript file: \(path)"
        case "rs": return "Analyze this Rust file: \(path)"
        case "go": return "Analyze this Go file: \(path)"
        case "rb": return "Analyze this Ruby file: \(path)"
        case "java": return "Analyze this Java file: \(path)"
        case "md", "markdown": return "Summarize this document: \(path)"
        case "json": return "Read and explain this JSON file: \(path)"
        case "yaml", "yml": return "Read and explain this YAML file: \(path)"
        case "toml": return "Read and explain this TOML file: \(path)"
        case "png", "jpg", "jpeg", "gif", "webp": return "Analyze this image: \(path)"
        case "pdf": return "Summarize this PDF: \(path)"
        case "csv": return "Analyze this CSV data: \(path)"
        case "html", "css": return "Analyze this web file: \(path)"
        default: return "Analyze this file: \(path)"
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: Spacing.sm) {
            if let orch = uxOrchestrator {
                statusIndicator(state: orch.state)
            }

            if let last = uxOrchestrator?.lastStory {
                Text("Last task:")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
                Text(truncated(last.intent))
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitSecondary)
                    .lineLimit(1)
            } else {
                Text("Nothing running")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }

            if let orch = uxOrchestrator, orch.state == .failed,
               let suggestion = orch.recoverySuggestion,
               let intent = orch.failedIntent {
                recoveryButton(suggestion: suggestion, intent: intent)
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                memoryBadge
                statusDot
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, 4)
        .background(Color.orbitSurface.opacity(0.5))
    }

    private func recoveryButton(suggestion: String, intent: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9))
            Text(suggestion)
                .font(.orbitCaptionSmall)
        }
        .foregroundStyle(.orbitAccent)
        .contentShape(Rectangle())
        .onTapGesture {
            let modified = "Simplify: \(intent)"
            composerText = modified
            uxOrchestrator?.retryWithModifiedIntent(modified)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orbitAccent.opacity(0.1))
        .clipShape(Capsule())
    }

    private func statusIndicator(state: UXState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 5, height: 5)
            Text(state.progressDescription)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
        }
    }

    private var memoryBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "memorychip")
                .font(.system(size: 8))
                .foregroundStyle(.orbitTertiary)
            Text(memoryUsageString)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
        }
        .onReceive(memoryUpdate) { _ in
            memoryUsageString = MemoryUsage.current
        }
    }

    private var statusDot: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.orbitSuccess)
                .frame(width: 4, height: 4)
            Text("Ready")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
        }
    }

    private func truncated(_ s: String) -> String {
        s.count > 40 ? String(s.prefix(40)) + "..." : s
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
        case .interpreting, .planning, .awaitingConfirmation: .orbitAccent
        case .executing: .orbitAccent
        case .failed: .orbitError
        case .completed: .orbitSuccess
        case .cancelled: .orbitWarning
        }
    }
}
