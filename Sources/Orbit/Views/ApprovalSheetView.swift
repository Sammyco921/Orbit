import SwiftUI

struct ApprovalSheetView: View {
    let request: ToolApprovalRequest
    let onResponse: (ToolApprovalResponse) -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 20) {
            iconHeader
            titleSection
            detailsSection
            Divider()
            actionButtons
        }
        .padding()
        .frame(width: 440)
    }

    private var iconHeader: some View {
        ZStack {
            Circle()
                .fill(Color.orange.opacity(0.1))
                .frame(width: 64, height: 64)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 28))
                .foregroundColor(.orange)
        }
    }

    private var titleSection: some View {
        VStack(spacing: 4) {
            Text("Orbit wants to")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(actionTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
    }

    private var actionTitle: String {
        switch request.toolName {
        case "fileWrite", "write": return "write to a file"
        case "readFile", "cat", "read": return "read a file"
        case "terminal", "bash", "shell": return "run a terminal command"
        case "screenshot": return "capture the screen"
        case "browserNavigate", "browserExtract": return "browse the web"
        case "gitCommit", "gitPush": return "modify git history"
        case "fileDelete", "delete": return "delete files"
        case "finderSearch", "search", "grep", "find": return "search your files"
        default: return "use \"\(request.toolName)\""
        }
    }

    private var detailsSection: some View {
        VStack(spacing: 8) {
            if !request.input.isEmpty {
                Button(showDetails ? "Hide Details" : "Show Details") {
                    withAnimation(.easeOut(duration: 0.15)) { showDetails.toggle() }
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if destructiveCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("This will affect \(destructiveCount) file\(destructiveCount != 1 ? "s" : "")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var destructiveCount: Int {
        switch request.toolName {
        case "fileWrite", "write", "fileDelete", "delete":
            return request.input["path"] != nil ? 1 : 0
        case "gitCommit", "gitPush":
            return 3
        default:
            return 0
        }
    }

    private var actionButtons: some View {
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
                .keyboardShortcut(.return, modifiers: [])
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
}
