import SwiftUI

struct TimelineView: View {
    @Environment(\.uxOrchestrator) private var uxOrchestrator
    @Environment(\.navigateToSection) private var navigateToSection
    @Binding var prefillSuggestion: String

    @State private var expandedGroups: Set<String> = []
    @State private var expandedSteps: Set<UUID> = []
    @State private var showNarrativeCompression = false

    private let autoCollapseThreshold = 6

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let orch = uxOrchestrator, let story = orch.currentStory {
                        timelineContent(orch: orch, story: story)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
            .onChange(of: uxOrchestrator?.currentStory?.steps.count) { _ in
                scrollToLatest(proxy: proxy)
            }
            .onChange(of: uxOrchestrator?.state) { _ in
                scrollToLatest(proxy: proxy)
            }
        }
    }

    // MARK: - Computed flags

    private var cognitiveMode: CognitivePresentationEngine.Mode {
        guard let orch = uxOrchestrator, let story = orch.currentStory else { return .simple }
        let duration = story.executionStartedAt.map { Date().timeIntervalSince($0) }
        return CognitivePresentationEngine.computeMode(
            stepCount: story.steps.count,
            executionDuration: duration,
            uniqueToolCount: Set(story.steps.map(\.toolID)).count,
            totalStreamedTokens: story.steps.reduce(0) { $0 + ($1.streamedTokens?.count ?? 0) }
        )
    }

    private var stabilizedMode: Bool { cognitiveMode == .dense }
    private var compactMode: Bool { cognitiveMode == .dense }

    private var activeGroupID: String? {
        guard let orch = uxOrchestrator else { return nil }
        let groups = buildGroups(from: orch.currentStory?.steps ?? [])
        let activeIndex = orch.currentStory?.steps.firstIndex { $0.status == .inProgress }
        return groups.first { group in
            group.steps.contains { $0.status == .inProgress }
        }?.id
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "orbit")
                .font(.system(size: 40))
                .foregroundStyle(.orbitAccent.opacity(0.25))

            Spacer().frame(height: Spacing.md)

            Text(OrbitVoice.Execution.noActiveTask)
                .font(.orbitTitle2)
                .foregroundStyle(.orbitPrimary)

            Spacer().frame(height: Spacing.xs)

            Text(OrbitVoice.Execution.noActiveTaskDescription)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Spacer().frame(height: Spacing.xl)

            VStack(spacing: Spacing.sm) {
                SuggestionButton(icon: "magnifyingglass", label: "Analyze something", hint: "Analyze the current project structure") {
                    prefillSuggestion = "Analyze the current project structure"
                }
                SuggestionButton(icon: "terminal", label: "Run a command", hint: "Run git status and show the current branch") {
                    prefillSuggestion = "Run git status and show the current branch"
                }
                SuggestionButton(icon: "questionmark.bubble", label: "Ask a question", hint: "What dependencies does this project use?") {
                    prefillSuggestion = "What dependencies does this project use?"
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Timeline Content

    private func timelineContent(orch: UXOrchestrator, story: ExecutionStory) -> some View {
        let groups = buildGroups(from: story.steps)
        let focusedID = focusedElementID(orch: orch, story: story)

        return VStack(spacing: stabilizedMode ? 0 : 0) {
            IntentCardView(intent: story.intent, state: orch.state) { edited in
                orch.submit(intent: edited)
            }

            if orch.state != .idle {
                intentAnchorLine(story: story)
            }

            if orch.state == .interpreting {
                InterpretationBlockView(intent: story.intent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if case .awaitingConfirmation = orch.state {
                ActionPreviewView(story: story, onApprove: {
                    orch.confirmPlan()
                }, onReject: {
                    orch.rejectPlan()
                }, onEdit: { newIntent in
                    orch.submit(intent: newIntent)
                })
                .padding(.vertical, Spacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !groups.isEmpty {
                if compactMode, let synth = buildNarrativeSynthesis(story: story) {
                    narrativeCompressionView(synthesis: synth)
                }

                VStack(spacing: groupSpacing) {
                    ForEach(groups) { group in
                        StepGroupView(
                            group: group,
                            isExpanded: expandedGroups.contains(group.id),
                            expandedSteps: $expandedSteps,
                            activeGroupID: activeGroupID,
                            focusedID: focusedID,
                            stabilizedMode: stabilizedMode,
                            compactMode: compactMode,
                            totalSteps: story.steps.count,
                            onToggle: { toggleGroup(group.id) }
                        )
                    }
                }
                .padding(.vertical, groupPadding)
            }

            if let summary = story.summary {
                SummaryBlockView(summary: summary, didFail: story.steps.contains { $0.status == .failed || $0.status == .timedOut }, didCancel: story.steps.contains { $0.status == .cancelled })
                    .transition(.opacity)
                    .opacity(focusOpacity(for: "summary", focusedID: focusedID))
            }

            if orch.state == .idle || orch.state == .completed || orch.state == .failed || orch.state == .cancelled {
                if story.summary != nil || orch.state == .completed || orch.state == .failed || orch.state == .cancelled {
                    postExecutionActions(orch: orch, story: story)
                        .transition(.opacity)
                }
                Spacer().frame(height: Spacing.sm)
            }
        }
        .animation(stabilizedMode ? nil : AnimationToken.Ease.mediumInOut, value: orch.state)
        .animation(stabilizedMode ? nil : AnimationToken.Ease.slowInOut, value: story.steps.count)
        .animation(stabilizedMode ? nil : AnimationToken.Ease.standardOut, value: story.summary != nil)
    }

    private var groupSpacing: CGFloat {
        compactMode ? 2 : stabilizedMode ? 4 : 6
    }

    private var groupPadding: CGFloat {
        compactMode ? 2 : stabilizedMode ? 4 : Spacing.xs
    }

    // MARK: - Group Building

    private func buildGroups(from steps: [StoryStep]) -> [StepGroup] {
        guard !steps.isEmpty else { return [] }

        if steps.count <= 4 {
            return [StepGroup(
                id: "execution",
                label: "Execution",
                icon: "arrow.triangle.branch",
                summary: "\(steps.count) step\(steps.count != 1 ? "s" : "")",
                steps: steps
            )]
        }

        let planningTools: Set<String> = ["echo", "interpret", "plan"]
        let outputTools: Set<String> = ["echo", "output", "result"]

        var groups: [StepGroup] = []
        var currentSteps: [StoryStep] = []
        var currentPhase = phaseForStep(steps[0], planningTools: planningTools, outputTools: outputTools)

        for step in steps {
            let phase = phaseForStep(step, planningTools: planningTools, outputTools: outputTools)
            if phase != currentPhase, !currentSteps.isEmpty {
                groups.append(makeGroup(phase: currentPhase, steps: currentSteps))
                currentSteps = []
                currentPhase = phase
            }
            currentSteps.append(step)
        }

        if !currentSteps.isEmpty {
            groups.append(makeGroup(phase: currentPhase, steps: currentSteps))
        }

        // Ensure auto-collapse for older groups when > threshold
        let totalSteps = steps.count
        if totalSteps > autoCollapseThreshold, expandedGroups.isEmpty {
            for group in groups where !group.steps.contains(where: { $0.status == .inProgress || $0.status == .pending }) {
                expandedGroups.insert(group.id)
            }
        }

        return groups
    }

    private enum StepPhase: String {
        case planning, execution, output
    }

    private func phaseForStep(_ step: StoryStep, planningTools: Set<String>, outputTools: Set<String>) -> StepPhase {
        let toolID = step.toolID ?? ""
        if planningTools.contains(toolID), step.order <= 1 { return .planning }
        if outputTools.contains(toolID), step.status == .completed, step.output != nil, step.order > 1 { return .output }
        return .execution
    }

    private func makeGroup(phase: StepPhase, steps: [StoryStep]) -> StepGroup {
        let stepDescriptions = steps.map { $0.description }
        let summary = stepDescriptions.count == 1 ? stepDescriptions[0] : "\(stepDescriptions.count) steps"

        switch phase {
        case .planning:
            return StepGroup(id: "planning", label: "Plan", icon: "list.clipboard", summary: summary, steps: steps)
        case .execution:
            let tool = steps.compactMap { $0.toolID }.first ?? "execution"
            return StepGroup(id: "execution-\(tool)", label: toolLabel(for: tool), icon: toolIcon(for: tool), summary: summary, steps: steps)
        case .output:
            return StepGroup(id: "output", label: "Output", icon: "doc.text", summary: summary, steps: steps)
        }
    }

    private func toolLabel(for toolID: String) -> String {
        switch toolID {
        case "echo": "Conversation"
        case "screenshot", "browser", "web": "Browser"
        case "search", "grep", "find": "Search"
        case "git": "Git"
        case "write", "create", "edit": "Edit"
        case "read", "cat": "Read"
        case "terminal", "bash", "shell": "Terminal"
        default: toolID.capitalized
        }
    }

    private func toolIcon(for toolID: String) -> String {
        switch toolID {
        case "echo": "bubble.left"
        case "screenshot", "browser", "web": "safari"
        case "search", "grep", "find": "magnifyingglass"
        case "git": "arrow.triangle.branch"
        case "write", "create", "edit": "pencil"
        case "read", "cat": "book"
        case "terminal", "bash", "shell": "terminal"
        default: "gearshape"
        }
    }

    // MARK: - Focus Control

    private func focusedElementID(orch: UXOrchestrator, story: ExecutionStory) -> String? {
        if story.steps.contains(where: { $0.status == .inProgress }) { return "step" }
        if let summary = story.summary, orch.state == .completed || orch.state == .failed || orch.state == .cancelled { return "summary" }
        return nil
    }

    private func focusOpacity(for element: String, focusedID: String?) -> CGFloat {
        guard let focusedID else { return 1.0 }
        if element == focusedID { return 1.0 }
        return compactMode ? 0.85 : 0.7
    }

    // MARK: - Narrative Compression

    private func buildNarrativeSynthesis(story: ExecutionStory) -> String? {
        let completed = story.steps.filter { $0.status == .completed }
        guard !completed.isEmpty, completed.count >= 3 else { return nil }
        let descriptions = completed.prefix(3).map { "- \($0.description)" }
        let remaining = completed.count - 3
        var result = descriptions.joined(separator: "\n")
        if remaining > 0 {
            result += "\n- +\(remaining) more step\(remaining != 1 ? "s" : "")"
        }
        return result
    }

    // MARK: - Group Toggle
    private func toggleGroup(_ id: String) {
        withAnimation(AnimationToken.Ease.standardOut) {
            if expandedGroups.contains(id) {
                expandedGroups.remove(id)
            } else {
                expandedGroups.insert(id)
            }
        }
    }

    private func narrativeCompressionView(synthesis: String) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(AnimationToken.Ease.standardOut) {
                    showNarrativeCompression.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                    Text(OrbitVoice.Execution.summaryHeader)
                        .font(.orbitCaptionSmall)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .rotationEffect(.degrees(showNarrativeCompression ? 90 : 0))
                }
                .foregroundStyle(.orbitAccent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(Color.orbitAccent.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            if showNarrativeCompression {
                Text(synthesis)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.orbitSurfaceSecondary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, Spacing.xs)
    }

    // MARK: - Intent Anchor

    @ViewBuilder
    private func intentAnchorLine(story: ExecutionStory) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "orbit")
                .font(.system(size: 10))
                .foregroundStyle(.orbitAccent.opacity(0.5))
            Text(OrbitVoice.Intent.working(on: story.intent))
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Post-Execution Actions

    @ViewBuilder
    private func postExecutionActions(orch: UXOrchestrator, story: ExecutionStory) -> some View {
        VStack(spacing: Spacing.sm) {
            Divider().overlay(Color.orbitBorder)
                .padding(.vertical, Spacing.xs)

            Text("What would you like to do next?")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: Spacing.sm) {
                ActionChip(icon: "arrow.counterclockwise", label: "Run another task") {
                    orch.reset()
                    prefillSuggestion = ""
                }
                ActionChip(icon: "square.and.arrow.down", label: "Save as workflow") {
                    navigateToSection?.navigate(.agents)
                }
                ActionChip(icon: "doc.text", label: "View artifacts") {
                    navigateToSection?.navigate(.files)
                }
                ActionChip(icon: "clock.arrow.circlepath", label: "View in history") {
                    navigateToSection?.navigate(.history)
                }
            }
        }
        .padding(.top, Spacing.sm)
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        if let last = uxOrchestrator?.currentStory?.steps.last {
            withAnimation(AnimationToken.Ease.standardOut) { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

// MARK: - Step Group View

private struct StepGroupView: View {
    let group: StepGroup
    let isExpanded: Bool
    @Binding var expandedSteps: Set<UUID>
    let activeGroupID: String?
    let focusedID: String?
    let stabilizedMode: Bool
    let compactMode: Bool
    let totalSteps: Int
    let onToggle: () -> Void

    private var isActiveGroup: Bool { activeGroupID == group.id }

    var body: some View {
        VStack(spacing: 0) {
            groupHeader

            if isExpanded {
                VStack(spacing: compactMode ? 2 : stabilizedMode ? 3 : 4) {
                    ForEach(Array(group.steps.enumerated()), id: \.element.id) { _, step in
                        let stepBinding = Binding<Set<UUID>>(
                            get: { expandedSteps },
                            set: { expandedSteps = $0 }
                        )
                        ExecutionStepCardView(
                            step: step,
                            totalSteps: totalSteps,
                            expandedSteps: stepBinding,
                            stabilizedMode: stabilizedMode,
                            compactMode: compactMode,
                            isFocused: step.status == .inProgress
                        )
                        .id(step.id)
                        .transition(.asymmetric(
                            insertion: stabilizedMode
                                ? AnimationToken.Transition.default
                                : AnimationToken.Transition.slideTop.animation(AnimationToken.Ease.slowOut),
                            removal: AnimationToken.Transition.default.animation(AnimationToken.Ease.quickOut)
                        ))
                        .opacity(focusOpacity(for: step))
                    }
                }
                .padding(.leading, 8)
                .padding(.top, 2)
                .padding(.bottom, compactMode ? 2 : 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(isActiveGroup ? Color.orbitAccent.opacity(0.02) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(isActiveGroup ? Color.orbitAccent.opacity(0.08) : .clear, lineWidth: 1)
        )
    }

    private var groupHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: group.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(isActiveGroup ? .orbitAccent : .orbitSecondary)

                Text(group.label)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(isActiveGroup ? .orbitAccent : .orbitPrimary)

                if isActiveGroup {
                    Text("\u{2014} Now running")
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitAccent)
                }

                Spacer()

                Text(group.summary)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8))
                    .foregroundStyle(.orbitTertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(isActiveGroup ? Color.orbitAccent.opacity(0.04) : Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func focusOpacity(for step: StoryStep) -> CGFloat {
        guard let focusedID else { return 1.0 }
        if step.status == .inProgress { return 1.0 }
        if focusedID == "step", step.status != .inProgress { return compactMode ? 0.8 : 0.6 }
        return 1.0
    }
}

// MARK: - Models

private struct StepGroup: Identifiable {
    let id: String
    let label: String
    let icon: String
    let summary: String
    let steps: [StoryStep]
}

// MARK: - Suggestion Button

private struct SuggestionButton: View {
    let icon: String
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.orbitAccent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitPrimary)
                    Text(hint)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                }
                Spacer()
                Image(systemName: "arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(.orbitTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Action Chip

private struct ActionChip: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.orbitCaptionSmall)
            }
            .foregroundStyle(.orbitSecondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
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
