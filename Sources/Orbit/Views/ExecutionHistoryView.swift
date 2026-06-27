import SwiftUI

struct ExecutionHistoryView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @Environment(\.navigateToSection) private var navigateToSection
    @State private var stories: [HistoryStoryGroup] = []
    @State private var isLoading = true
    @State private var expandedID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.orbitBorder)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitBackground)
        .task { await loadHistory() }
    }

    private var header: some View {
        HStack {
            Text("Execution History")
                .font(.orbitHeadline)
                .foregroundStyle(.orbitPrimary)
            Spacer()
            Text("\(stories.count) story\(stories.count != 1 ? "ies" : "y")")
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
            Button("Refresh") {
                Task { await loadHistory() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(Color.orbitBackground)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            Spacer()
            ProgressView("Loading history\u{2026}")
            Spacer()
        } else if stories.isEmpty {
            VStack(spacing: 0) {
                Spacer()
                UnifiedEmptyState(case: .history) {
                    navigateToSection?.navigate(.workspace)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            }
        } else {
            ScrollView {
                VStack(spacing: Spacing.xs) {
                    ForEach(stories) { group in
                        StoryCardView(
                            group: group,
                            isExpanded: expandedID == group.id,
                            onToggle: {
                                withAnimation(AnimationToken.Ease.standardOut) {
                                    expandedID = expandedID == group.id ? nil : group.id
                                }
                            }
                        )
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    private func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let entries = orchestrator.runtime.auditService.recent(limit: 200)
        let grouped = Dictionary(grouping: entries) { $0.sessionId }
        stories = grouped.compactMap { sessionId, entries in
            guard let first = entries.min(by: { $0.createdAt < $1.createdAt }) else { return nil }
            return HistoryStoryGroup(id: sessionId, entries: entries.sorted { $0.createdAt < $1.createdAt }, createdAt: first.createdAt)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - Display Model

private struct HistoryStoryGroup: Identifiable {
    let id: String
    let entries: [ExecutionLogEntry]
    let createdAt: Date

    var stepCount: Int { entries.count }
    var allSucceeded: Bool { entries.allSatisfy { $0.outcome == "succeeded" || $0.outcome == "completed" || $0.outcome == "approved" } }
    var anyFailed: Bool { entries.contains { $0.outcome == "failed" || $0.outcome == "error" || $0.outcome == "denied" } }
}

// MARK: - Story Card

private struct StoryCardView: View {
    let group: HistoryStoryGroup
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.sm) {
                    outcomeDot
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.orbitBodySmall)
                            .foregroundStyle(.orbitPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text("\(group.stepCount) step\(group.stepCount != 1 ? "s" : "")")
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitTertiary)
                            Text("\u{00B7}")
                                .foregroundStyle(.orbitTertiary)
                            Text(duration)
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitTertiary)
                            Text("\u{00B7}")
                                .foregroundStyle(.orbitTertiary)
                            Text(group.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.orbitTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 10)
                .padding(.horizontal, Spacing.sm)
                .background(Color.orbitSurface)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            }
            .buttonStyle(.plain)

            if isExpanded {
                storyDetail
                    .transition(AnimationToken.Transition.slideTop)
            }
        }
    }

    @ViewBuilder
    private var storyDetail: some View {
        VStack(spacing: 0) {
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(outcomeColor(entry.outcome))
                            .frame(width: 8, height: 8)
                        if index < group.entries.count - 1 {
                            Rectangle()
                                .fill(Color.orbitTimelineLine)
                                .frame(width: 1.5)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.toolName)
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitPrimary)
                        if let detail = entry.errorDetail {
                            Text(detail)
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitError)
                        }
                    }
                    .padding(.vertical, 4)

                    Spacer()

                    Text(entry.createdAt, style: .time)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                }
                .padding(.horizontal, Spacing.sm + Spacing.xxs)
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(Color.orbitSurfaceSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    private var title: String {
        group.entries.first?.toolName ?? "Unknown"
    }

    private var duration: String {
        guard let first = group.entries.first, let last = group.entries.last else { return "" }
        let elapsed = last.createdAt.timeIntervalSince(first.createdAt)
        if elapsed < 60 {
            return "\(Int(elapsed))s"
        }
        return "\(Int(elapsed / 60))m \(Int(elapsed.truncatingRemainder(dividingBy: 60)))s"
    }

    private var outcomeDot: some View {
        if group.allSucceeded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orbitSuccess)
        } else if group.anyFailed {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orbitError)
        } else {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orbitWarning)
        }
    }

    private func outcomeColor(_ outcome: String) -> Color {
        switch outcome {
        case "succeeded", "success", "completed", "approved": .orbitSuccess
        case "failed", "error", "denied", "rejected": .orbitError
        case "cancelled": .orbitWarning
        default: .orbitTertiary
        }
    }
}
