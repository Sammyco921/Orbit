import SwiftUI

struct PermissionDashboardView: View {
    let definitions: [ToolDefinition]
    @State private var searchText = ""

    private var sorted: [ToolDefinition] {
        let result: [ToolDefinition]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            result = definitions
        } else {
            let q = searchText.lowercased()
            result = definitions.filter { $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q) }
        }
        return result.sorted { a, b in
            let aSensitive = a.requiredPermission == .requiresApproval
            let bSensitive = b.requiredPermission == .requiresApproval
            if aSensitive != bSensitive { return aSensitive }
            return a.name < b.name
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search tools...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding()

            List(sorted, id: \.id) { def in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def.name)
                            .font(.subheadline)
                        Text(def.id)
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(def.requiredPermission == .requiresApproval ? "Requires approval" : "No approval needed")
                        .font(.caption)
                        .foregroundColor(def.requiredPermission == .requiresApproval ? .orange : .secondary)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.plain)
        }
        .frame(width: 520, height: 400)
    }
}
