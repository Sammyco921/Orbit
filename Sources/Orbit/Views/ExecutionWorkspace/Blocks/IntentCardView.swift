import SwiftUI

struct IntentCardView: View {
    let intent: String
    let state: UXState
    let onReRun: ((String) -> Void)?

    @State private var isEditing = false
    @State private var editedText: String = ""

    init(intent: String, state: UXState, onReRun: ((String) -> Void)? = nil) {
        self.intent = intent
        self.state = state
        self.onReRun = onReRun
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "person.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orbitPrimary)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Edit your request...", text: $editedText, axis: .vertical)
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitPrimary)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            withAnimation(.easeOut(duration: 0.15)) { isEditing = false }
                        }
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitTertiary)
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Re-run") {
                            onReRun?(editedText)
                            withAnimation(.easeOut(duration: 0.15)) { isEditing = false }
                        }
                        .font(.orbitCaptionSmall)
                        .foregroundStyle(.orbitAccent)
                        .disabled(editedText.trimmingCharacters(in: .whitespaces).isEmpty)
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(intent)
                        .font(.orbitBodySmall)
                        .foregroundStyle(.orbitPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if isTerminalState, !isEditing {
                Button {
                    editedText = intent
                    withAnimation(.easeOut(duration: 0.15)) { isEditing = true }
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(.orbitAccent)
                }
                .buttonStyle(.plain)
                .help("Edit and re-run")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Spacing.md)
    }

    private var isTerminalState: Bool {
        state == .completed || state == .failed || state == .cancelled
    }
}
