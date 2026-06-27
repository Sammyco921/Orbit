import SwiftUI

struct InspectorPanelView: View {
    @Environment(\.uxOrchestrator) private var uxOrchestrator
    @State private var selectedTab: InspectorTab = .info

    enum InspectorTab: String, CaseIterable {
        case info = "Info"
        case activity = "Activity"
        case debug = "Debug"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(InspectorTab.allCases, id: \.rawValue) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(selectedTab == tab ? .orbitPrimary : .orbitTertiary)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(selectedTab == tab ? Color.orbitSurfaceSecondary : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.top, Spacing.xs)

            Divider()
                .overlay(Color.orbitBorder)

            // Tab content
            ScrollView {
                switch selectedTab {
                case .info: infoContent
                case .activity: activityContent
                case .debug: debugContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.orbitSurface)
    }

    private var infoContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Group {
                infoRow("Execution ID", uxOrchestrator?.currentStory?.id.uuidString.prefix(8).description ?? "—")
                infoRow("State", uxOrchestrator?.state.progressDescription ?? "idle")
                infoRow("Duration", formattedDuration)
                infoRow("Tool Calls", "\(uxOrchestrator?.currentStory?.steps.count ?? 0)")
                infoRow("Steps Completed", "\(uxOrchestrator?.currentStory?.steps.filter { $0.status == .completed }.count ?? 0)")
                infoRow("Failed Steps", "\(uxOrchestrator?.currentStory?.steps.filter { $0.status == .failed }.count ?? 0)")
            }
            .padding(.horizontal, Spacing.md)
        }
        .padding(.vertical, Spacing.md)
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(uxOrchestrator?.currentStory?.steps ?? []) { step in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text(step.timestamp, style: .time)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                        .frame(width: 50, alignment: .leading)
                    statusIcon(step.status)
                        .frame(width: 12)
                    Text(step.description)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
            }

            if (uxOrchestrator?.currentStory?.steps ?? []).isEmpty {
                Text("No activity yet")
                    .font(.orbitCaption)
                    .foregroundStyle(.orbitTertiary)
                    .padding(Spacing.md)
            }
        }
        .padding(.vertical, Spacing.sm)
    }

    private var debugContent: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let story = uxOrchestrator?.currentStory {
                debugSection("Story") {
                    debugRow("Intent", story.intent)
                    debugRow("Steps", "\(story.steps.count)")
                    debugRow("Has Result", story.result != nil ? "yes" : "no")
                    debugRow("Has Summary", story.summary != nil ? "yes" : "no")
                }

                debugSection("Activity Log") {
                    ForEach(story.steps) { step in
                        debugRow(
                            step.timestamp.formatted(date: .omitted, time: .standard),
                            "\(step.description) → \(step.status.rawValue)"
                        )
                    }
                }
            } else {
                Text("No execution data available")
                    .font(.orbitCaption)
                    .foregroundStyle(.orbitTertiary)
                    .padding(Spacing.md)
            }
        }
        .padding(.vertical, Spacing.md)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitPrimary)
            Spacer()
        }
    }

    private func debugSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .padding(.horizontal, Spacing.md)
            content()
        }
    }

    private func debugRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
    }

    private var formattedDuration: String {
        guard let started = uxOrchestrator?.executionStartedAt else { return "—" }
        let end = uxOrchestrator?.executionEndedAt ?? Date()
        let elapsed = end.timeIntervalSince(started)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func statusIcon(_ status: StoryStepStatus) -> some View {
        let icon: String
        switch status {
        case .pending: icon = "circle"
        case .inProgress: icon = "circle.fill"
        case .completed: icon = "checkmark"
        case .failed: icon = "xmark"
        case .timedOut: icon = "clock"
        case .cancelled: icon = "minus"
        }
        return Image(systemName: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(statusColor(status))
    }

    private func statusColor(_ status: StoryStepStatus) -> Color {
        switch status {
        case .pending: .orbitTertiary
        case .inProgress: .orbitAccent
        case .completed: .orbitSuccess
        case .failed: .orbitError
        case .timedOut: .orbitWarning
        case .cancelled: .orbitWarning
        }
    }
}
