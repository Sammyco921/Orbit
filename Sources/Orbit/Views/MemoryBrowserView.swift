import SwiftUI

struct MemoryBrowserView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var conversationItems: [MemoryItem] = []
    @State private var globalItems: [MemoryItem] = []
    @State private var userFacts: [(id: Int64, fact: String, category: String, confidence: Float)] = []
    @State private var selectedTab = 0
    @State private var selectedIds = Set<String>()
    @State private var isDeleting = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Conversation Memories").tag(0)
                Text("Global Memories").tag(1)
                Text("User Facts").tag(2)
            }
            .pickerStyle(.segmented)
            .padding()

            List(selection: $selectedIds) {
                switch selectedTab {
                case 0:
                    if conversationItems.isEmpty {
                        Text("No conversation memories yet").foregroundColor(.secondary).font(.caption)
                    }
                    ForEach(conversationItems) { item in
                        memoryRow(item)
                            .tag(item.id)
                    }
                case 1:
                    if globalItems.isEmpty {
                        Text("No global memories yet").foregroundColor(.secondary).font(.caption)
                    }
                    ForEach(globalItems) { item in
                        memoryRow(item)
                            .tag(item.id)
                    }
                case 2:
                    if userFacts.isEmpty {
                        Text("No user facts extracted yet").foregroundColor(.secondary).font(.caption)
                    }
                    ForEach(userFacts, id: \.id) { fact in
                        factRow(fact)
                    }
                default: EmptyView()
                }
            }

            if !selectedIds.isEmpty {
                HStack {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Label("Delete \(selectedIds.count) selected", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(isDeleting)
                    Spacer()
                }
                .padding()
            }
        }
        .frame(width: 500, height: 400)
        .navigationTitle("Memory Browser")
        .task { await loadData() }
    }

    @ViewBuilder
    private func memoryRow(_ item: MemoryItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.type).font(.caption).foregroundColor(.secondary)
                if let role = item.role {
                    Text(role).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(formatDate(item.createdAt)).font(.caption2).foregroundColor(.secondary)
            }
            Text(item.content)
                .font(.body)
                .lineLimit(3)
            if !item.conversationId.isEmpty {
                Text("Conversation: \(item.conversationId.prefix(8))...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func factRow(_ fact: (id: Int64, fact: String, category: String, confidence: Float)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fact.category).font(.caption).foregroundColor(.secondary)
                Spacer()
                Text("\(String(format: "%.0f", fact.confidence * 100))% confidence")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(fact.fact).font(.body)
        }
        .padding(.vertical, 4)
    }

    private func loadData() async {
        guard let store = orchestrator.runtime.memoryService.memoryStore else { return }
        do {
            conversationItems = try store.getAllItems()
            globalItems = try store.searchGlobalItems(limit: 100)
            userFacts = try store.getUserFacts()
        } catch {}
    }

    private func deleteSelected() {
        guard let store = orchestrator.runtime.memoryService.memoryStore else { return }
        isDeleting = true
        do {
            if selectedTab == 0 {
                try store.deleteItems(ids: Array(selectedIds))
            } else if selectedTab == 1 {
                try store.deleteGlobalItems(ids: Array(selectedIds))
            }
            selectedIds.removeAll()
            Task { await loadData() }
        } catch {}
        isDeleting = false
    }

    private func formatDate(_ timestamp: TimeInterval) -> String {
        let d = Date(timeIntervalSince1970: timestamp)
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}
