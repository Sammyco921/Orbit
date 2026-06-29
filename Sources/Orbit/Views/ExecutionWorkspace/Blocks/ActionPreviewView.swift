import SwiftUI

struct ActionPreviewView: View {
    let story: ExecutionStory
    let onApprove: () -> Void
    let onReject: () -> Void
    let onEdit: (String) -> Void

    @State private var showingEstimate = false
    @State private var estimatedSeconds: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            headerRow
            Divider().overlay(Color.orbitBorder)
            stepsList
            if showingEstimate {
                estimateRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider().overlay(Color.orbitBorder)
            actionButtons
        }
        .padding(Spacing.md)
        .background(Color.orbitSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.orbitBorder, lineWidth: 1)
        )
        .task {
            estimatedSeconds = estimateDuration(steps: story.steps)
            withAnimation(.easeOut(duration: 0.3)) { showingEstimate = true }
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "eye")
                .font(.system(size: 14))
                .foregroundStyle(.orbitAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Action Preview")
                    .font(.orbitHeadline)
                    .foregroundStyle(.orbitPrimary)
                Text("Orbit will perform the following steps")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }
            Spacer()
        }
    }

    private var stepsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(story.steps.enumerated()), id: \.element.id) { _, step in
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.orbitSuccess)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.description)
                            .font(.orbitBodySmall)
                            .foregroundStyle(.orbitPrimary)
                        if let summary = step.actionSummary {
                            Text(summary)
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitTertiary)
                        }
                    }
                    Spacer()
                    if let toolID = step.toolID {
                        toolBadge(toolID)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, Spacing.sm)
                .background(Color.orbitSurfaceSecondary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func toolBadge(_ toolID: String) -> some View {
        Text(toolDisplayName(toolID))
            .font(.orbitCaptionSmall)
            .foregroundStyle(.orbitAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orbitAccent.opacity(0.08))
            .clipShape(Capsule())
    }

    private func toolDisplayName(_ toolID: String) -> String {
        switch toolID {
        case "echo": "Chat"
        case "screenshot", "browserNavigate", "browserExtract": "Browser"
        case "search", "grep", "find", "finderSearch": "Search"
        case "gitStatus", "gitCommit", "gitPush": "Git"
        case "readFile", "cat": "Read"
        case "fileWrite", "write": "Write"
        case "terminal", "bash", "shell": "Terminal"
        case "imageAnalyze": "Vision"
        default: toolID.capitalized
        }
    }

    private var estimateRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "clock")
                .font(.system(size: 10))
                .foregroundStyle(.orbitTertiary)
            Text("Estimated time:")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
            Text(formatDuration(estimatedSeconds))
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitPrimary)
                .fontWeight(.medium)
            if estimatedSeconds > 10 {
                Text("(\(story.steps.count) step\(story.steps.count != 1 ? "s" : ""))")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }
            Spacer()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onReject) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                    Text("Cancel")
                        .font(.orbitBodySmall)
                }
                .foregroundStyle(.orbitSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 8)
                .background(Color.orbitSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orbitBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onApprove) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("Approve")
                        .font(.orbitBodySmall)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 8)
                .background(Color.orbitAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func estimateDuration(steps: [StoryStep]) -> Int {
        var total = 0
        for step in steps {
            switch step.toolID {
            case "echo": total += 8
            case "screenshot", "browserNavigate", "browserExtract": total += 6
            case "search", "grep", "find", "finderSearch": total += 4
            case "gitStatus", "gitCommit", "gitPush": total += 3
            case "readFile", "cat": total += 2
            case "fileWrite", "write": total += 3
            case "terminal", "bash", "shell": total += 5
            case "imageAnalyze": total += 4
            default: total += 5
            }
        }
        return max(total, 2)
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) seconds" }
        let minutes = seconds / 60
        let secs = seconds % 60
        return "\(minutes)m \(secs)s"
    }
}
