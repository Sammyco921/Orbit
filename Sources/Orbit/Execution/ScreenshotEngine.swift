import Foundation
import AppKit
import CoreGraphics

final class ScreenshotEngine {

    enum CaptureMode {
        case allDisplays
        case mainDisplay
        case activeWindow
        case selection
    }

    func capture(mode: CaptureMode = .activeWindow) -> Data? {
        switch mode {
        case .allDisplays:
            return captureAllDisplays()
        case .mainDisplay:
            return captureMainDisplay()
        case .activeWindow:
            return captureFrontmostWindow()
        case .selection:
            return captureSelection()
        }
    }

    func captureAndSave(mode: CaptureMode = .activeWindow, to directory: URL) -> URL? {
        guard let data = capture(mode: mode) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "screenshot_\(timestamp).png"
        let fileURL = directory.appendingPathComponent(filename)
        try? data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - Main Display

    private func captureMainDisplay() -> Data? {
        guard let main = CGMainDisplayID() as CGDirectDisplayID? else { return nil }
        guard let image = CGDisplayCreateImage(main) else { return nil }
        return pngData(from: image)
    }

    // MARK: - All Displays

    private func captureAllDisplays() -> Data? {
        var screens = [CGImage]()
        var totalWidth = 0
        var maxHeight = 0

        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let image = CGDisplayCreateImage(screenNumber)
            else { continue }
            screens.append(image)
            totalWidth += image.width
            maxHeight = max(maxHeight, image.height)
        }

        guard !screens.isEmpty else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: totalWidth,
            height: maxHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        var xOffset: Int = 0
        for img in screens {
            ctx.draw(img, in: CGRect(x: xOffset, y: 0, width: img.width, height: img.height))
            xOffset += img.width
        }

        guard let combined = ctx.makeImage() else { return nil }
        return pngData(from: combined)
    }

    // MARK: - Active Window

    private func captureFrontmostWindow() -> Data? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let appPID = app.processIdentifier as pid_t?
        else { return nil }

        let windowInfo = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        let targetWindow = windowInfo?.first { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == appPID,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], width > 100,
                  let height = bounds["Height"], height > 100
            else { return false }
            return true
        }

        guard let target = targetWindow,
              let bounds = target[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"],
              let windowNumber = target[kCGWindowNumber as String] as? CGWindowID
        else { return captureMainDisplay() }

        let rect = CGRect(x: x, y: y, width: width, height: height)
        guard let image = CGWindowListCreateImage(rect, .optionIncludingWindow, windowNumber, [.boundsIgnoreFraming, .nominalResolution])
        else { return captureMainDisplay() }

        return pngData(from: image)
    }

    // MARK: - Interactive Selection

    private func captureSelection() -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        var resultData: Data?

        DispatchQueue.main.async {
            let overlay = SelectionOverlayController()
            overlay.onCapture = { data in
                resultData = data
                semaphore.signal()
            }
            overlay.onCancel = {
                semaphore.signal()
            }
            overlay.beginCapture()
        }

        semaphore.wait()
        return resultData
    }

    // MARK: - Helpers

    private func pngData(from image: CGImage) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Interactive Selection Overlay

private final class SelectionOverlayController: NSObject {
    var onCapture: ((Data) -> Void)?
    var onCancel: (() -> Void)?

    private var window: NSWindow?
    private var startPoint: NSPoint?
    private var selectionRect: NSRect?
    private let overlayView = SelectionOverlayView()

    func beginCapture() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame

        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        overlayView.frame = contentView.bounds
        overlayView.autoresizingMask = [.width, .height]
        contentView.addSubview(overlayView)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.contentView = contentView
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.level = .screenSaver
        win.makeKeyAndOrderFront(nil)
        win.acceptsMouseMovedEvents = true

        self.window = win

        overlayView.onRectSelected = { [weak self] rect in
            guard let self else { return }
            self.window?.orderOut(nil)

            guard rect.width > 10 && rect.height > 10 else {
                self.onCancel?()
                return
            }

            let screenRect = screen.frame
            let captureRect = CGRect(
                x: rect.origin.x,
                y: screenRect.height - rect.origin.y - rect.height,
                width: rect.width,
                height: rect.height
            )

            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let image = CGDisplayCreateImage(displayID, rect: captureRect)
            else {
                self.onCancel?()
                return
            }

            let bitmap = NSBitmapImageRep(cgImage: image)
            let data = bitmap.representation(using: .png, properties: [:])
            self.onCapture?(data ?? Data())
        }
    }
}

private final class SelectionOverlayView: NSView {
    var onRectSelected: ((NSRect) -> Void)?

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var trackingArea: NSTrackingArea?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupTracking()
    }

    private func setupTracking() {
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let rect = currentRect else {
            startPoint = nil
            currentRect = nil
            needsDisplay = true
            return
        }
        onRectSelected?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill()
        dirtyRect.fill()

        if let rect = currentRect {
            let path = NSBezierPath(rect: rect)
            NSColor.clear.setFill()
            path.fill()

            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()

            let info = "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.white
            ]
            let size = info.size(withAttributes: attrs)
            let textRect = NSRect(
                x: rect.minX + 6,
                y: rect.minY - size.height - 6,
                width: size.width + 8,
                height: size.height + 4
            )
            let bg = NSBezierPath(roundedRect: textRect, xRadius: 3, yRadius: 3)
            NSColor.black.withAlphaComponent(0.7).setFill()
            bg.fill()

            info.draw(at: NSPoint(x: textRect.minX + 4, y: textRect.minY + 2), withAttributes: attrs)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.white.withAlphaComponent(0.6)
            ]
            let text = "Drag to select a region"
            let size = text.size(withAttributes: attrs)
            text.draw(
                at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                withAttributes: attrs
            )
        }
    }
}
