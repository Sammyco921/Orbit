import SwiftUI
import AppKit

struct ConversationSearchView: View {
    @Binding var isPresented: Bool
    let orchestrator: Orchestrator

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var results: [(conversation: Conversation, match: SearchMatch)] {
        ConversationSearchService.search(query: searchText, in: orchestrator.conversations)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                searchBar
                if !results.isEmpty {
                    Divider().overlay(Color.orbitBorder)
                    resultsList
                } else if !searchText.isEmpty {
                    noResults
                }
            }
            .frame(width: 620)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
            .orbitShadow(24, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
            .background(QuickActionBarKeyHandler2(
                onUp: moveUp,
                onDown: moveDown,
                onEscape: { isPresented = false }
            ))
        }
        .onAppear { isFocused = true }
        .onChange(of: searchText) { _, _ in selectedIndex = 0 }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.orbitTertiary)
                .font(.system(size: 16))
            TextField("Search conversations...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($isFocused)
                .onSubmit(executeSelected)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.orbitTertiary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.conversation.id) { index, result in
                    resultRow(result: result, isSelected: index == selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { selectResult(index) }
                }
            }
            .padding(.bottom, Spacing.xs)
        }
        .frame(maxHeight: 400)
    }

    private var noResults: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.orbitTertiary)
            Text("No conversations match \"\(searchText)\"")
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
        }
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Result Row

    private func resultRow(result: (conversation: Conversation, match: SearchMatch), isSelected: Bool) -> some View {
        let conv = result.conversation
        return HStack(spacing: Spacing.sm) {
            Image(systemName: "message")
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .orbitAccent : .orbitSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(conv.title)
                        .font(.orbitBodySmall)
                        .foregroundStyle(isSelected ? .orbitPrimary : .orbitPrimary)
                        .lineLimit(1)
                    if conv.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orbitTertiary)
                    }
                }
                Text(snippet(for: result.match))
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(conv.updatedAt, style: .relative)
                .font(.orbitCaptionSmall)
                .foregroundStyle(.orbitTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? Color.orbitAccentDim : Color.clear)
    }

    private func snippet(for match: SearchMatch) -> String {
        switch match {
        case .titleMatch:
            return "Title match"
        case .contentMatch(let content):
            if content.count > 80 {
                return String(content.prefix(80)) + "..."
            }
            return content
        }
    }

    // MARK: - Navigation

    private func moveUp() {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func moveDown() {
        guard !results.isEmpty else { return }
        selectedIndex = min(results.count - 1, selectedIndex + 1)
    }

    private func selectResult(_ index: Int) {
        guard index >= 0, index < results.count else { return }
        let conv = results[index].conversation
        orchestrator.selectConversation(conv.id)
        isPresented = false
    }

    private func executeSelected() {
        guard !results.isEmpty else { return }
        let clampedIndex = min(selectedIndex, results.count - 1)
        selectResult(clampedIndex)
    }
}

// MARK: - Search Logic

enum SearchMatch: Equatable {
    case titleMatch
    case contentMatch(String)
}

enum ConversationSearchService {
    static func search(query: String, in conversations: [Conversation]) -> [(conversation: Conversation, match: SearchMatch)] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        let q = trimmed.lowercased()
        var results: [(Conversation, SearchMatch)] = []

        for conv in conversations {
            if conv.title.lowercased().contains(q) {
                results.append((conv, .titleMatch))
                continue
            }
            for msg in conv.messages where msg.content.lowercased().contains(q) {
                let snippet = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                results.append((conv, .contentMatch(snippet.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines))))
                break
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.1 == .titleMatch && rhs.1 != .titleMatch { return true }
            if lhs.1 != .titleMatch && rhs.1 == .titleMatch { return false }
            return lhs.0.updatedAt > rhs.0.updatedAt
        }
    }
}

// MARK: - Keyboard Handler

private struct QuickActionBarKeyHandler2: NSViewRepresentable {
    let onUp: () -> Void
    let onDown: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUp = onUp
        context.coordinator.onDown = onDown
        context.coordinator.onEscape = onEscape
        context.coordinator.installIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onEscape: (() -> Void)?
        private var monitor: Any?

        func installIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.specialKey {
                case .upArrow:
                    onUp?()
                    return nil
                case .downArrow:
                    onDown?()
                    return nil
                default:
                    if event.keyCode == 53 {
                        onEscape?()
                        return nil
                    }
                    return event
                }
            }
        }

        deinit {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }
}
