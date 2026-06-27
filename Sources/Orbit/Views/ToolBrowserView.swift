import SwiftUI

struct ToolBrowserView: View {
    let definitions: [ToolDefinition]
    @State private var searchText = ""
    @State private var selectedPermission: String?

    private var filtered: [ToolDefinition] {
        let result: [ToolDefinition]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            result = definitions
        } else {
            let q = searchText.lowercased()
            result = definitions.filter { def in
                def.name.lowercased().contains(q) ||
                def.id.lowercased().contains(q) ||
                def.description.lowercased().contains(q)
            }
        }
        if let perm = selectedPermission {
            return result.filter { $0.requiredPermission.rawValue == perm }
        }
        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search tools by name, ID, or description...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)

                HStack(spacing: 6) {
                    filterChip("All", selected: selectedPermission == nil) { selectedPermission = nil }
                    filterChip("No approval", selected: selectedPermission == Permission.none.rawValue) { selectedPermission = Permission.none.rawValue }
                    filterChip("Requires approval", selected: selectedPermission == Permission.requiresApproval.rawValue) { selectedPermission = Permission.requiresApproval.rawValue }
                    Spacer()
                    Text("\(filtered.count) tools")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            List(filtered, id: \.id) { def in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(def.name)
                            .font(.subheadline.bold())
                        Spacer()
                        permissionBadge(def.requiredPermission)
                    }
                    Text(def.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text(def.id)
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(.secondary)
                        if !def.inputSchema.parameters.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(def.inputSchema.parameters.count) parameter(s)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !def.inputSchema.parameters.isEmpty {
                        ForEach(def.inputSchema.parameters, id: \.name) { param in
                            HStack(spacing: 4) {
                                Text(param.name)
                                    .font(.caption2)
                                    .monospaced()
                                Text(param.type.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if param.required {
                                    Text("required")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                                Text("— \(param.description)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .frame(width: 520, height: 480)
    }

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(selected ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func permissionBadge(_ permission: Permission) -> some View {
        Text(permission == .none ? "No approval" : "Requires approval")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(permission == .none ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundColor(permission == .none ? .green : .orange)
            .cornerRadius(4)
    }
}
