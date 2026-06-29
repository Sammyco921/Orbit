import SwiftUI
import AppKit

struct QuickActionBarView: View {
    @Binding var isPresented: Bool
    let orchestrator: Orchestrator
    let uxOrchestrator: UXOrchestrator?

    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    private var filteredActions: [(QuickAction, QuickActionCategory)] {
        QuickActionRegistry.filtered(by: searchText)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                searchBar
                if !filteredActions.isEmpty {
                    Divider().overlay(Color.orbitBorder)
                    resultsList
                } else if !searchText.isEmpty {
                    noResults
                }
            }
            .frame(width: 560)
            .background(Color.orbitSurface)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
            .orbitShadow(24, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(Color.orbitBorder, lineWidth: 1)
            )
            .background(QuickActionBarKeyHandler(
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
            TextField("Search actions...", text: $searchText)
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
        let grouped = Dictionary(grouping: filteredActions) { $0.1 }
        let sortedCategories = grouped.keys.sorted { $0.rawValue < $1.rawValue }

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sortedCategories, id: \.self) { category in
                    if let actions = grouped[category] {
                        SectionHeader(title: category.rawValue, count: actions.count)

                        ForEach(Array(actions.enumerated()), id: \.element.0.id) { (offset, item) in
                            let globalIndex = globalIndex(for: category, offset: offset, grouped: grouped, sortedCategories: sortedCategories)
                            actionRow(item: item, isSelected: globalIndex == selectedIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { selectAction(globalIndex) }
                        }
                    }
                }
            }
            .padding(.bottom, Spacing.xs)
        }
        .frame(maxHeight: 360)
    }

    private var noResults: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.orbitTertiary)
            Text("No actions match \"\(searchText)\"")
                .font(.orbitBodySmall)
                .foregroundStyle(.orbitSecondary)
        }
        .padding(.vertical, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Row

    private func actionRow(item: (QuickAction, QuickActionCategory), isSelected: Bool) -> some View {
        let action = item.0
        return HStack(spacing: Spacing.sm) {
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? .orbitAccent : .orbitSecondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(action.title)
                    .font(.orbitBodySmall)
                    .foregroundStyle(isSelected ? .orbitPrimary : .orbitPrimary)
                Text(action.subtitle)
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitTertiary)
            }

            Spacer()

            if action.isInstant {
                Text("Instant")
                    .font(.orbitCaptionSmall)
                    .foregroundStyle(.orbitInfo)
                    .orbitChip(color: .orbitInfo.opacity(0.1))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(isSelected ? Color.orbitAccentDim : Color.clear)
    }

    // MARK: - Navigation

    private func globalIndex(for category: QuickActionCategory, offset: Int, grouped: [QuickActionCategory: [(QuickAction, QuickActionCategory)]], sortedCategories: [QuickActionCategory]) -> Int {
        var index = 0
        for cat in sortedCategories {
            if cat == category {
                return index + offset
            }
            index += grouped[cat]?.count ?? 0
        }
        return offset
    }

    private var flattenedActions: [(QuickAction, QuickActionCategory)] {
        filteredActions
    }

    private func moveUp() {
        guard !filteredActions.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    private func moveDown() {
        guard !filteredActions.isEmpty else { return }
        selectedIndex = min(filteredActions.count - 1, selectedIndex + 1)
    }

    private func selectAction(_ index: Int) {
        guard index >= 0, index < filteredActions.count else { return }
        let action = filteredActions[index].0
        performAction(action)
    }

    private func executeSelected() {
        guard !filteredActions.isEmpty else { return }
        let clampedIndex = min(selectedIndex, filteredActions.count - 1)
        let action = filteredActions[clampedIndex].0
        performAction(action)
    }

    private func performAction(_ action: QuickAction) {
        isPresented = false
        if action.isInstant {
            performInstantAction(action)
        } else {
            uxOrchestrator?.submitQuickAction(intent: action.intent)
        }
    }

    private func performInstantAction(_ action: QuickAction) {
        switch action.title {
        case "Open in Xcode":
            openInXcode()
        case "Open in Finder":
            revealInFinder()
        default:
            break
        }
    }

    private func openInXcode() {
        guard let ws = orchestrator.activeWorkspace, let path = ws.path else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        if let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
            NSWorkspace.shared.open([url], withApplicationAt: xcodeURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealInFinder() {
        guard let ws = orchestrator.activeWorkspace, let path = ws.path else { return }
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: (path as NSString).deletingLastPathComponent)
    }
}

// MARK: - Keyboard Handler (AppKit)

private struct QuickActionBarKeyHandler: NSViewRepresentable {
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
