import SwiftUI

struct KnowledgeBaseView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var knowledgeBases: [KnowledgeBase] = []
    @State private var showCreate = false
    @State private var isIngesting = Set<String>()
    @State private var ingestProgress: [String: String] = [:]
    @State private var selectedKB: KnowledgeBase?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Knowledge Bases").font(.headline)
                Spacer()
                Button { showCreate = true } label: {
                    Label("New KB", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()

            if knowledgeBases.isEmpty {
                ContentUnavailableView(
                    "No Knowledge Bases",
                    systemImage: "books.vertical",
                    description: Text("Add a file, folder, git repo, or URL to index.")
                )
            } else {
                List(knowledgeBases, selection: $selectedKB) { kb in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: icon(for: kb.sourceType))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(kb.name).font(.body)
                            Spacer()
                            if isIngesting.contains(kb.id) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .controlSize(.small)
                            }
                        }
                        if let desc = kb.description {
                            Text(desc).font(.caption).foregroundColor(.secondary)
                        }
                        HStack {
                            Text(kb.sourceType).font(.caption2).foregroundColor(.secondary)
                            if let path = kb.sourcePath {
                                Text(path).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let progress = ingestProgress[kb.id] {
                                Text(progress).font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Re-index") {
                            Task { await ingest(kb.id) }
                        }
                        .disabled(isIngesting.contains(kb.id))
                        Divider()
                        Button("Delete", role: .destructive) {
                            deleteKB(kb.id)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 450, height: 350)
        .navigationTitle("Knowledge Bases")
        .sheet(isPresented: $showCreate) {
            CreateKnowledgeBaseView { name, description, sourceType, sourcePath in
                try await createKB(name: name, description: description, sourceType: sourceType, sourcePath: sourcePath)
            }
        }
        .task { await loadKBs() }
    }

    private func loadKBs() async {
        guard let service = orchestrator.runtime.knowledgeBaseService else { return }
        do { knowledgeBases = try service.getAll() } catch {}
    }

    private func createKB(name: String, description: String?, sourceType: String, sourcePath: String?) async throws {
        guard let service = orchestrator.runtime.knowledgeBaseService else { return }
        let kb = try service.create(name: name, description: description, sourceType: sourceType, sourcePath: sourcePath)
        await loadKBs()
        Task { await ingest(kb.id) }
    }

    private func ingest(_ id: String) async {
        guard let service = orchestrator.runtime.knowledgeBaseService else { return }
        isIngesting.insert(id)
        do {
            try await service.ingest(id: id) { msg in
                Task { @MainActor in ingestProgress[id] = msg }
            }
        } catch {
            ingestProgress[id] = "Failed: \(error.localizedDescription)"
        }
        isIngesting.remove(id)
        await loadKBs()
    }

    private func deleteKB(_ id: String) {
        guard let service = orchestrator.runtime.knowledgeBaseService else { return }
        try? service.delete(id: id)
        Task { await loadKBs() }
    }

    private func icon(for type: String) -> String {
        switch type {
        case "file": return "doc"
        case "folder": return "folder"
        case "repo": return "arrow.triangle.branch"
        case "url": return "globe"
        default: return "books.vertical"
        }
    }
}

struct CreateKnowledgeBaseView: View {
    @Environment(\.dismiss) private var dismiss
    let onSubmit: (String, String?, String, String?) async throws -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var sourceType = "folder"
    @State private var sourcePath = ""
    @State private var isSubmitting = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("New Knowledge Base").font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Description (optional)", text: $description)
                .textFieldStyle(.roundedBorder)

            Picker("Source Type", selection: $sourceType) {
                Text("File").tag("file")
                Text("Folder").tag("folder")
                Text("Git Repo").tag("repo")
                Text("URL").tag("url")
            }
            .pickerStyle(.segmented)

            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                if sourceType == "url" || sourceType == "repo" {
                    TextField(sourceType == "url" ? "https://example.com/docs" : "https://github.com/user/repo", text: $sourcePath)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField(sourceType == "file" ? "Path to file" : "Path to folder", text: $sourcePath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        browseForSource()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if let error {
                Text(error).font(.caption).foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                Button("Create & Index") {
                    Task { await submit() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || sourcePath.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func browseForSource() {
        let panel = NSOpenPanel()
        if sourceType == "file" {
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
        } else {
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        sourcePath = url.path
    }

    private func submit() async {
        isSubmitting = true
        error = nil
        do {
            try await onSubmit(name.trimmingCharacters(in: .whitespaces), description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description.trimmingCharacters(in: .whitespaces), sourceType, sourcePath.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
    }
}
