import SwiftUI

struct ArtifactManagerView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var artifacts: [ArtifactItem] = []
    @State private var selectedType: Artifact.ArtifactType?
    @State private var searchText = ""
    @State private var selection = Set<UUID>()

    private let store = ArtifactStore()

    private var filtered: [ArtifactItem] {
        var result = artifacts
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }
        if !searchText.isEmpty {
            result = result.filter { $0.filename.localizedCaseInsensitiveContains(searchText) }
        }
        return result
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedType) {
                Text("All")
                    .tag(nil as Artifact.ArtifactType?)
                ForEach(Artifact.ArtifactType.allCases, id: \.self) { type in
                    HStack {
                        Image(systemName: icon(for: type))
                        Text(type.rawValue.capitalized)
                    }
                    .tag(type as Artifact.ArtifactType?)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search artifacts…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    Button("Refresh") { refresh() }
                        .buttonStyle(.bordered)
                }
                .padding(8)

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Artifacts",
                        systemImage: "doc.questionmark",
                        description: Text("Artifacts are created when tools generate files\u{2014}like screenshots, documents, or spreadsheets.")
                    )
                } else {
                    Table(filtered, selection: $selection) {
                        TableColumn("Name") { item in
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: item.type))
                                    .foregroundStyle(.tint)
                                    .frame(width: 20)
                                Text(item.filename)
                                    .lineLimit(1)
                            }
                        }
                        TableColumn("Type", value: \.filename).width(80)
                        TableColumn("Size") { item in
                            Text(item.sizeFormatted).foregroundColor(.secondary)
                        }
                        .width(80)
                        TableColumn("Date") { item in
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundColor(.secondary)
                        }
                        TableColumn("Conversation") { item in
                            Text(item.conversationTitle ?? "—")
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contextMenu(forSelectionType: UUID.self) { items in
                        Button("Open") {
                            for id in items {
                                if let item = filtered.first(where: { $0.id == id }) {
                                    store.open(item)
                                }
                            }
                        }
                        Button("Reveal in Finder") {
                            for id in items {
                                if let item = filtered.first(where: { $0.id == id }) {
                                    store.revealInFinder(item)
                                }
                            }
                        }
                        Button("Delete") {
                            for id in items {
                                if let item = filtered.first(where: { $0.id == id }) {
                                    try? store.delete(item)
                                }
                            }
                            refresh()
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        artifacts = store.scan(conversations: orchestrator.conversations)
    }

    private func icon(for type: Artifact.ArtifactType?) -> String {
        switch type {
        case .markdown: "doc.text"
        case .spreadsheet: "tablecells"
        case .presentation: "rectangle.on.rectangle"
        case .document: "doc.richtext"
        case .pdf: "doc.viewfinder"
        case .folder: "folder"
        case .code: "chevron.left.forwardslash.chevron.right"
        case nil: "doc"
        }
    }
}
