import Foundation
import AppKit
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "global-hotkey")

/// Manages a global hotkey (Cmd+Shift+O) that brings up the Orbit overlay
public final class GlobalHotkeyService {
    private var monitor: Any?
    private var eventTap: CFMachPort?
    public var onHotkeyPressed: (() -> Void)?

    private let hotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    private let hotkeyKey: UInt16 = 31 // 'O' key code

    public func start() {
        // Use event monitor approach — no accessibility permissions needed
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == hotkeyModifiers && event.keyCode == hotkeyKey {
                log.notice("Global hotkey detected: Cmd+Shift+O")
                onHotkeyPressed?()
            }
        }
        log.notice("Global hotkey monitor started")
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        log.notice("Global hotkey monitor stopped")
    }

    deinit {
        stop()
    }
}
