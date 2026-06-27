import SwiftUI

struct SummaryBlockView: View {
    let summary: SummarySection
    let didFail: Bool
    let didCancel: Bool

    init(summary: SummarySection, didFail: Bool, didCancel: Bool = false) {
        self.summary = summary
        self.didFail = didFail
        self.didCancel = didCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: statusIcon)
                    .font(.system(size: 10))
                    .foregroundStyle(statusColor)
                Text(statusLabel)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(statusColor)
            }

            Text(summary.whatWasDone)
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !summary.resultSummary.isEmpty {
                Text(summary.resultSummary)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitSecondary)
            }

            if didFail || didCancel {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb")
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitWarning)
                    Text(suggestion)
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Spacing.md)
    }

    private var suggestion: String {
        if didCancel {
            OrbitVoice.Error.recoverySuggestion(for: OrbitVoice.Error.cancelledMidStep)
        } else {
            OrbitVoice.Error.recoverySuggestion(for: OrbitVoice.Error.jobFailedMidStream)
        }
    }

    private var statusIcon: String {
        didCancel ? "minus.circle.fill" : didFail ? "xmark.circle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        didCancel ? .orbitWarning : didFail ? .orbitError : .orbitSuccess
    }

    private var statusLabel: String {
        didCancel ? OrbitVoice.Status.cancelled : didFail ? OrbitVoice.Status.failed : OrbitVoice.Status.done
    }
}
