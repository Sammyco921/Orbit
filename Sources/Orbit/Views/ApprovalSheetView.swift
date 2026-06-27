import SwiftUI

struct ApprovalSheetView: View {
    let request: ToolApprovalRequest
    let onResponse: (ToolApprovalResponse) -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text("Tool Requires Approval")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                LabeledContent("Tool", value: request.toolName)
                    .font(.subheadline)

                if !request.input.isEmpty {
                    Button(showDetails ? "Hide Details" : "Show Details") {
                        showDetails.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.accentColor)

                    if showDetails {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(request.input.keys.sorted()), id: \.self) { key in
                                HStack(alignment: .top) {
                                    Text(key + ":")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 80, alignment: .trailing)
                                    Text(request.input[key] ?? "")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: { onResponse(.deny) }) {
                        Label("Deny", systemImage: "xmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)

                    Button(action: { onResponse(.allow) }) {
                        Label("Allow", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 12) {
                    Button(action: { onResponse(.allowOnce) }) {
                        Text("Allow Once")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { onResponse(.allowForSession) }) {
                        Text("Always Allow for Session")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(width: 420)
    }
}
