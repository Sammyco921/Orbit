import SwiftUI

struct ExecutionStepCardView: View {
    let step: StoryStep
    let totalSteps: Int
    @Binding var expandedSteps: Set<UUID>
    var stabilizedMode: Bool = false
    var compactMode: Bool = false
    var isFocused: Bool = false

    private var isLast: Bool { step.order >= totalSteps - 1 }
    private var isExpanded: Bool { expandedSteps.contains(step.id) }

    var body: some View {
        HStack(alignment: .top, spacing: compactMode ? 6 : Spacing.sm) {
            timelineIndicator

            VStack(alignment: .leading, spacing: compactMode ? 1 : 3) {
                stepTitleRow

                agentBadges

                if isExpanded || !compactMode {
                    stepSummary
                    streamingContent
                    outputContent
                    microLabelRow
                    progressiveDetails
                } else if step.status == .completed || step.status == .failed || step.status == .timedOut || step.status == .cancelled {
                    if let output = step.output, !output.isEmpty {
                        Text(output)
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
        }
        .padding(.vertical, compactMode ? 3 : 5)
        .padding(.horizontal, compactMode ? Spacing.sm : Spacing.md)
        .background(stepBackground)
        .clipShape(RoundedRectangle(cornerRadius: compactMode ? 4 : CornerRadius.md))
        .overlay(alignment: .leading) {
            if step.status == .failed || step.status == .timedOut || step.status == .cancelled {
                Rectangle()
                    .fill(accentBarColor)
                    .frame(width: 2.5)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.vertical, compactMode ? 2 : 4)
                    .transition(AnimationToken.Transition.default)
            }
        }
        .animation(stabilizedMode ? nil : AnimationToken.Ease.slowOut, value: step.status)
        .animation(stabilizedMode ? nil : AnimationToken.Ease.mediumOut, value: step.streamedTokens?.count ?? 0)
        .onTapGesture { toggleExpand() }
    }

    // MARK: - Step Title Row

    private var stepTitleRow: some View {
        HStack(spacing: 4) {
            Text(step.description)
                .font(compactMode ? .orbitCaptionSmall : .orbitBodySmall)
                .foregroundStyle(.orbitPrimary)
                .lineLimit(compactMode && !isExpanded ? 1 : nil)

            if step.toolInput != nil || step.traceID != nil {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 8))
                    .foregroundStyle(.orbitTertiary)
                    .opacity(isExpanded ? 0 : 1)
            }
        }
    }

    // MARK: - Agent Badges

    @ViewBuilder
    private var agentBadges: some View {
        if let names = step.agentNames, !names.isEmpty, let roles = step.agentRoles, !compactMode {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(zip(names, roles).enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 3) {
                            Image(systemName: agentIcon(for: pair.1))
                                .font(.system(size: 8))
                            Text(pair.0)
                                .font(.orbitCaptionSmall)
                        }
                        .foregroundStyle(.orbitInfo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orbitInfo.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private func agentIcon(for role: String) -> String {
        switch role.lowercased() {
        case "planner": "flowchart"
        case "executor": "wrench.and.screwdriver"
        case "researcher": "magnifyingglass"
        case "reviewer": "checkmark.seal"
        case "memory manager": "brain"
        default: "person.circle"
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private var stepSummary: some View {
        if let summary = step.actionSummary, step.status != .completed, step.status != .failed {
            Text(summary)
                .font(compactMode ? .orbitCaptionSmall : .orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
        }
    }

    // MARK: - Streaming

    @ViewBuilder
    private var streamingContent: some View {
        if step.status == .inProgress, let tokens = step.streamedTokens, !tokens.isEmpty {
            Text(tokens)
                .font(.orbitBody)
                .foregroundStyle(.orbitSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Output

    @ViewBuilder
    private var outputContent: some View {
        if let output = step.output, step.status != .inProgress {
            Text(output)
                .font(isExpanded ? .orbitBody : .orbitBody)
                .foregroundStyle(.orbitSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(isExpanded ? nil : compactMode ? 2 : 3)
        }
    }

    // MARK: - Micro Label

    @ViewBuilder
    private var microLabelRow: some View {
        if let label = microLabel {
            HStack(spacing: 4) {
                if step.status == .inProgress {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.orbitAccent)
                }
                Text(label)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(microLabelColor)
            }
        }
    }

    // MARK: - Progressive Disclosure

    @ViewBuilder
    private var progressiveDetails: some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 4) {
                if let input = step.toolInput {
                    detailRow(label: "Input", value: input)
                }
                if let trace = step.traceID {
                    detailRow(label: "Trace", value: trace)
                }
                if let decision = step.kernelDecision {
                    detailRow(label: "Decision", value: decision)
                }
                if let detail = step.detail {
                    detailRow(label: "Detail", value: detail)
                }
                if step.status == .failed || step.status == .timedOut {
                    recoverySuggestion
                }
            }
            .padding(.top, 2)
            .transition(AnimationToken.Transition.default)
        } else if !compactMode, step.status == .pending || step.status == .inProgress {
            EmptyView()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
            Text(value)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    // MARK: - Actions

    private func toggleExpand() {
        withAnimation(AnimationToken.Ease.standardOut) {
            if expandedSteps.contains(step.id) {
                expandedSteps.remove(step.id)
            } else {
                expandedSteps.insert(step.id)
            }
        }
    }

    // MARK: - Micro Label

    private var microLabel: String? {
        switch step.status {
        case .inProgress:
            if step.order == 0 { return agentPhaseLabel ?? OrbitVoice.Execution.working }
            if isLast { return OrbitVoice.Execution.finalizing }
            return OrbitVoice.Execution.continuing
        case .completed: return OrbitVoice.Execution.stepCompleted
        case .failed: return OrbitVoice.Execution.taskFailed
        case .timedOut: return OrbitVoice.Execution.timedOut
        case .cancelled: return OrbitVoice.Execution.taskCancelled
        case .pending: return nil
        }
    }

    private var agentPhaseLabel: String? {
        guard step.status == .inProgress else { return nil }
        let toolID = step.toolID ?? ""
        switch toolID {
        case "echo", "respondConversationally": return "Thinking..."
        case "screenshot", "browserNavigate", "browserExtract": return "Browsing..."
        case "search", "grep", "find", "finderSearch": return "Searching..."
        case "gitStatus", "gitCommit", "gitPush": return "Running git..."
        case "readFile", "cat": return "Reading..."
        case "fileWrite", "write": return "Writing..."
        case "terminal", "bash", "shell": return "Running command..."
        case "readFile", "imageAnalyze": return "Analyzing..."
        default:
            if let desc = step.description.lowercased() as String? {
                if desc.contains("search") || desc.contains("find") { return "Searching..." }
                if desc.contains("read") || desc.contains("load") { return "Reading..." }
                if desc.contains("write") || desc.contains("create") || desc.contains("save") { return "Writing..." }
                if desc.contains("git") || desc.contains("commit") || desc.contains("push") { return "Running git..." }
                if desc.contains("browser") || desc.contains("web") { return "Browsing..." }
                if desc.contains("think") || desc.contains("analyze") || desc.contains("understand") { return "Thinking..." }
            }
            return OrbitVoice.Execution.working
        }
    }

    @ViewBuilder
    private var recoverySuggestion: some View {
        let message: String = {
            if step.status == .timedOut {
                return OrbitVoice.Error.recoverySuggestion(for: OrbitVoice.Error.modelDisconnected)
            }
            if let detail = step.detail?.lowercased() {
                if detail.contains("tool") || detail.contains("execution") {
                    return OrbitVoice.Error.recoverySuggestion(for: OrbitVoice.Error.jobFailedMidStream)
                }
                if detail.contains("empty") || detail.contains("no result") {
                    return OrbitVoice.Error.recoverySuggestion(for: OrbitVoice.Error.toolEmptyResult)
                }
            }
            return OrbitVoice.Error.recoverySuggestion(for: "default")
        }()
        HStack(spacing: 4) {
            Image(systemName: "lightbulb")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitWarning)
            Text(message)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
        }
        .padding(.top, 2)
    }

    private var microLabelColor: Color {
        switch step.status {
        case .inProgress: .orbitAccent
        case .completed: .orbitSuccess
        case .failed: .orbitError
        case .timedOut: .orbitWarning
        case .cancelled: .orbitWarning
        case .pending: .orbitTertiary
        }
    }

    // MARK: - Background

    private var stepBackground: Color {
        switch step.status {
        case .inProgress: Color.orbitAccent.opacity(0.03)
        case .failed: Color.orbitError.opacity(0.04)
        case .timedOut: Color.orbitWarning.opacity(0.04)
        case .cancelled: Color.orbitWarning.opacity(0.04)
        default: isExpanded ? Color.orbitSurface.opacity(0.5) : Color.clear
        }
    }

    // MARK: - Timeline Indicator

    @ViewBuilder
    private var timelineIndicator: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(dotColor)
                .frame(width: compactMode ? 7 : 10, height: compactMode ? 7 : 10)
                .overlay(
                    Circle()
                        .stroke(lineBorderColor, lineWidth: step.status == .pending ? 1.5 : 0)
                )
            if !isLast {
                Rectangle()
                    .fill(Color.orbitTimelineLine)
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: compactMode ? 16 : 20)
    }

    private var dotColor: Color {
        switch step.status {
        case .pending: .clear
        case .inProgress: .orbitAccent
        case .completed: .orbitSuccess
        case .failed: .orbitError
        case .timedOut: .orbitWarning
        case .cancelled: .orbitWarning
        }
    }

    private var accentBarColor: Color {
        switch step.status {
        case .failed: .orbitError
        case .timedOut: .orbitWarning
        case .cancelled: .orbitWarning
        default: .clear
        }
    }

    private var lineBorderColor: Color {
        step.status == .pending ? Color.orbitTimelineLine : .clear
    }
}
