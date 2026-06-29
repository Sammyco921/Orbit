import AppKit
import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "menubar")

@MainActor
public final class OrbitMenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let orchestrator: Orchestrator
    private var pollingTimer: Timer?
    private var lastStatus: MenuBarStatus = .connecting

    public init(orchestrator: Orchestrator) {
        self.orchestrator = orchestrator

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 480)
        popover.behavior = .transient

        super.init()

        if let button = statusItem.button {
            button.image = Self.makeStatusImage(status: .connecting)
            button.action = #selector(togglePopover)
            button.target = self
        }

        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateIcon()
            }
        }

        log.notice("Menu bar controller initialized")
    }

    deinit {
        pollingTimer?.invalidate()
        log.notice("Menu bar controller deinitialized")
    }

    // MARK: - Actions

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        let contentView = MenuBarPanelView()
            .environment(orchestrator)
        let host = NSHostingController(rootView: contentView)
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
        }
    }

    func hidePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - Icon Updates

    func updateIcon() {
        let status = orchestrator.backgroundRuntime?.menuBarStatus ?? .connecting
        guard status != lastStatus else { return }
        lastStatus = status
        guard let button = statusItem.button else { return }
        button.image = Self.makeStatusImage(status: status)
        button.toolTip = Self.statusDescription(status)
    }

    func forceIconUpdate() {
        lastStatus = .connecting
        updateIcon()
    }

    // MARK: - Image Drawing

    private static func makeStatusImage(status: MenuBarStatus) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let inset: CGFloat = 3
        let dotRect = rect.insetBy(dx: inset, dy: inset)
        let dotPath = NSBezierPath(ovalIn: dotRect)

        let color = NSColor(
            red: status.tint.red,
            green: status.tint.green,
            blue: status.tint.blue,
            alpha: 1.0
        )
        color.set()
        dotPath.fill()

        if status == .running {
            let ringPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5))
            color.withAlphaComponent(0.3).set()
            ringPath.lineWidth = 2
            ringPath.stroke()
        } else if case .queued = status {
            // Pulsing ring for queued items
            let ringPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5))
            color.withAlphaComponent(0.5).set()
            ringPath.lineWidth = 1.5
            ringPath.stroke()
        } else if case .paused = status {
            // Dashed ring for paused
            let ringPath = NSBezierPath(ovalIn: dotRect.insetBy(dx: -1.5, dy: -1.5))
            color.withAlphaComponent(0.4).set()
            ringPath.lineWidth = 1.5
            let pattern: [CGFloat] = [3, 2]
            ringPath.setLineDash(pattern, count: 2, phase: 0)
            ringPath.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func statusDescription(_ status: MenuBarStatus) -> String {
        switch status {
        case .idle: return "Orbit — \(OrbitVoice.Status.idle)"
        case .running: return "Orbit — \(OrbitVoice.Status.running)"
        case .queued(let count): return "Orbit — \(OrbitVoice.Label.queueCount(count))"
        case .paused(let count): return "Orbit — \(OrbitVoice.Label.pauseCount(count))"
        case .failed: return "Orbit — \(OrbitVoice.Status.error)"
        case .connecting: return "Orbit — \(OrbitVoice.Status.connecting)"
        }
    }

    // MARK: - Shutdown

    func shutDown() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        hidePopover()
        NSStatusBar.system.removeStatusItem(statusItem)
        log.notice("Menu bar controller shut down")
    }
}
