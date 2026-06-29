import SwiftUI

struct ResultBlockView: View {
    let result: ResultSection
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(.orbitSuccess)
                Text("Result")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitSuccess)
                Spacer()

                HStack(spacing: Spacing.xxs) {
                    Button { copyResult() } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Copy result")
                    .overlay(alignment: .top) {
                        if showCopied {
                            Text("Copied")
                                .font(.orbitCaptionSmall)
                                .foregroundStyle(.orbitSuccess)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orbitSurface)
                                .clipShape(Capsule())
                                .offset(y: -22)
                                .transition(.opacity)
                        }
                    }

                    Button { /* future: export */ } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Export")

                    Button { /* future: save as workflow */ } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .help("Save as workflow")
                }
                .foregroundStyle(.orbitTertiary)
            }

            // Content (monospaced verbatim output)
            Text(result.content)
                .font(.orbitMono)
                .foregroundStyle(.orbitPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.md)
        .background(Color.orbitSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(Color.orbitBorder, lineWidth: 1)
        )
    }

    private func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.content, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { showCopied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeOut(duration: 0.2)) { showCopied = false }
        }
    }
}
