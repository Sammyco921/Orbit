import SwiftUI
import Orbit

@main
struct OrbitApp: App {
    @State private var orchestrator = Orchestrator()
    @State private var overlayPanel: OverlayPanel?
    @State private var menuBarController: OrbitMenuBarController?

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(orchestrator)
                .frame(minWidth: 740, minHeight: 480)
                .onAppear { setupMenuBar(); setupOverlay() }
        }
        .windowResizability(.contentMinSize)

        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { orchestrator.newConversation() }
                    .keyboardShortcut("n", modifiers: .command)
                Divider()
                NewWindowMenuItem()
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appSettings) {
                Button("Quick Action Overlay...") { showOverlay() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }

        SwiftUI.Settings {
            SettingsView().environment(orchestrator)
        }
    }

    private func setupMenuBar() {
        guard menuBarController == nil else { return }
        menuBarController = OrbitMenuBarController(orchestrator: orchestrator)
    }

    private func setupOverlay() {
        let panel = OverlayPanel(orchestrator: orchestrator)
        overlayPanel = panel
        orchestrator.runtime.hotkeyService.onHotkeyPressed = { [weak orchestrator] in
            guard let orchestrator else { return }
            Task { @MainActor in
                panel.showOverlay()
            }
        }
        if orchestrator.settings.launchAtLogin {
            try? LaunchAtLoginService.shared.register()
        }
    }

    private func showOverlay() {
        overlayPanel?.showOverlay()
    }
}

private struct NewWindowMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("New Window") { openWindow(id: "main") }
    }
}
