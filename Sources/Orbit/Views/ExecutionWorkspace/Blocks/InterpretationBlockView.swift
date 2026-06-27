import SwiftUI

struct InterpretationBlockView: View {
    let intent: String

    @State private var dotCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Circle()
                .fill(.orbitAccent)
                .frame(width: 10, height: 10)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Analyzing request")
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitAccent)
                    Text(String(repeating: ".", count: dotCount % 4))
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitAccent)
                        .frame(width: 16, alignment: .leading)
                }

                Text(intent)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Spacing.md)
        .task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                dotCount += 1
            }
        }
    }
}
