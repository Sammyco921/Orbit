import SwiftUI

struct ToolExecutionCardView: View {
    let step: StoryStep

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Divider().overlay(Color.orbitBorder)

            VStack(alignment: .leading, spacing: 4) {
                detailRow("Tool", step.description)
                detailRow("Status", step.status.displayName)
                if let detail = step.detail, !detail.isEmpty {
                    detailRow("Output", detail)
                }
                if let tokens = step.streamedTokens, !tokens.isEmpty {
                    detailRow("Stream", tokens)
                }
                if let input = step.toolInput, !input.isEmpty {
                    detailRow("Input", input)
                }
                if let mode = step.permissionMode {
                    detailRow("Permission", mode)
                }
                if let decision = step.kernelDecision {
                    detailRow("Decision", decision)
                }
                if let traceID = step.traceID {
                    detailRow("Trace ID", traceID)
                }
                detailRow("Timestamp", step.timestamp.formatted(date: .omitted, time: .standard))
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.orbitSurfaceSecondary.opacity(0.5))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text(label)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
