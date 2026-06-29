import AppKit
import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "overlay-panel")

/// A floating, Spotlight-like panel for quick AI actions
public final class OverlayPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>

    public init(orchestrator: Orchestrator) {
        let content = AnyView(OverlayContentView().environment(orchestrator))
        self.hostingView = NSHostingView(rootView: content)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 200),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = NSColor.clear
        level = .floating
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = hostingView

        // Close on Escape
        let closeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closeOverlay()
                return nil
            }
            return event
        }

        // Close when clicking outside
        let resignMonitor = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.closeOverlay()
        }

        objc_setAssociatedObject(self, "_closeMonitor", closeMonitor, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(self, "_resignObserver", resignMonitor, .OBJC_ASSOCIATION_RETAIN)
    }

    deinit {
        if let monitor = objc_getAssociatedObject(self, "_closeMonitor") as? AnyObject {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = objc_getAssociatedObject(self, "_resignObserver") {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    public func showOverlay() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 520
        let panelHeight: CGFloat = 200
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY + panelHeight / 2 + 40

        setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        makeKeyAndOrderFront(nil)
    }

    public func closeOverlay() {
        orderOut(nil)
    }
}

struct OverlayContentView: View {
    @Environment(Orchestrator.self) private var orchestrator
    @State private var query: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "orbit")
                    .font(.title2)
                    .foregroundStyle(.tint)

                TextField("Ask Orbit anything...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
            }

            if !query.isEmpty {
                HStack(spacing: 8) {
                    QuickActionButton(title: "Summarize", icon: "text.quote") {
                        sendAction("Summarize this")
                    }
                    QuickActionButton(title: "Explain", icon: "questionmark.circle") {
                        sendAction("Explain this")
                    }
                    QuickActionButton(title: "Translate", icon: "globe") {
                        sendAction("Translate this")
                    }
                    QuickActionButton(title: "Refactor", icon: "arrow.triangle.branch") {
                        sendAction("Refactor this")
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: 520)
        .padding()
        .onAppear { isFocused = true }
        .onSubmit { submitQuery() }
    }

    private func submitQuery() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            await orchestrator.sendMessage(query)
        }
        query = ""

        // Hide overlay
        if let window = NSApp.keyWindow as? OverlayPanel {
            window.closeOverlay()
        }
        // Bring main window forward
        NSApp.activate(ignoringOtherApps: true)
    }

    private func sendAction(_ action: String) {
        query = action
        submitQuery()
    }
}

private struct QuickActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}
