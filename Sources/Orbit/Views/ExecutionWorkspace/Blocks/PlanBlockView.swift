import SwiftUI

struct PlanBlockView: View {
    let steps: [StoryStep]
    let state: UXState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 12))
                    .foregroundStyle(.orbitAccent)
                Text("Plan (\(steps.count) step\(steps.count != 1 ? "s" : ""))")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitAccent)
                Spacer()
                if state == .planning || steps.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            // Steps
            VStack(spacing: 2) {
                ForEach(steps) { step in
                    HStack(spacing: Spacing.sm) {
                        // Step number
                        Text("\(step.order + 1)")
                            .font(.orbitCaptionSmall)
                            .foregroundStyle(.orbitTertiary)
                            .frame(width: 20, alignment: .leading)

                        // Status icon
                        statusIcon(for: step)
                            .frame(width: 16)

                        // Description + expected output
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.description)
                                .font(.orbitBodySmall)
                                .foregroundStyle(.orbitPrimary)
                            if let expected = step.expectedOutput {
                                Text(expected)
                                    .font(.orbitCaptionSmall)
                                    .foregroundStyle(.orbitTertiary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, Spacing.sm)
                    .background(stepBackground(step))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.orbitSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.orbitBorder, lineWidth: 1)
        )
    }

    private func statusIcon(for step: StoryStep) -> some View {
        switch state {
        case .executing(let current, _):
            if step.order < current {
                return Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.orbitSuccess)
            } else if step.order == current {
                return Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orbitAccent)
            } else {
                return Image(systemName: "circle")
                    .font(.system(size: 8))
                    .foregroundStyle(.orbitTertiary)
            }
        case .completed:
            return Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orbitSuccess)
        case .failed:
            return Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.orbitError)
        default:
            return Image(systemName: "circle")
                .font(.system(size: 8))
                .foregroundStyle(.orbitTertiary)
        }
    }

    private func stepBackground(_ step: StoryStep) -> Color {
        guard case .executing(let current, _) = state else { return .clear }
        return step.order == current ? Color.orbitAccent.opacity(0.06) : .clear
    }
}
