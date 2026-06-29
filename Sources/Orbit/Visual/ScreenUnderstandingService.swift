import Foundation
import OSLog
import Vision
import AppKit

private let log = Logger(subsystem: "com.orbit", category: "screen-understanding")

/// Service that combines Vision OCR + Accessibility API to understand what's on screen
final class ScreenUnderstandingService {
    private let screenshotEngine = ScreenshotEngine()
    private let scriptExecutor = ScriptExecutor(timeoutSeconds: 10)
    private let ocrQueue = DispatchQueue(label: "com.orbit.vision.ocr", qos: .userInitiated)

    /// Capture the current screen and detect all UI elements
    func captureCurrentScreen() async throws -> ScreenSnapshot {
        // 1. Take a screenshot
        let artifactsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.orbit/screenshots")
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

        guard let screenshotURL = screenshotEngine.captureAndSave(mode: .mainDisplay, to: artifactsDir) else {
            throw OrbitError.screenCaptureFailed
        }

        return try await analyzeScreenshot(at: screenshotURL)
    }

    /// Analyze a screenshot at a given path for UI elements and text
    func analyzeScreenshot(at url: URL) async throws -> ScreenSnapshot {
        async let ocrText = performOCR(at: url)
        async let axElements = detectAccessibilityElements()
        async let frontmostApp = getFrontmostApp()

        let text = try await ocrText
        let elements = try await axElements
        let app = try await frontmostApp

        return ScreenSnapshot(
            timestamp: Date(),
            elements: elements,
            ocrText: text,
            frontmostApp: app
        )
    }

    /// Find an element matching a natural language description
    func findElement(matching description: String, in snapshot: ScreenSnapshot) -> VisualElement? {
        let query = description.lowercased()

        // Score-based matching: check labels, text content, type, position
        var scored: [(VisualElement, Int)] = []

        for elem in snapshot.elements {
            var score = 0
            let searchText = "\(elem.label) \(elem.textContent ?? "")".lowercased()

            // Exact match on label or text
            if searchText == query { score += 100 }
            // Contains the query
            if searchText.contains(query) { score += 50 }
            // Type match (e.g., "button" → .button)
            if query.contains(elem.type.displayName.lowercased()) || query.contains(elem.type.rawValue.lowercased()) {
                score += 20
            }
            // Position hints
            if query.contains("top") && elem.frame.midY < 300 { score += 10 }
            if query.contains("bottom") && elem.frame.midY > 600 { score += 10 }
            if query.contains("left") && elem.frame.midX < 300 { score += 10 }
            if query.contains("right") && elem.frame.midX > 900 { score += 10 }

            scored.append((elem, score))
        }

        return scored.sorted { $0.1 > $1.1 }.first?.0
    }

    /// Find form fields on screen
    func detectFormFields(in snapshot: ScreenSnapshot) -> [VisualElement] {
        snapshot.elements.filter { $0.type == .textField || $0.type == .dropdown || $0.type == .checkbox }
    }

    /// Generate a structured description of the current screen for LLM consumption
    func describeScreen(_ snapshot: ScreenSnapshot) -> String {
        var parts: [String] = []

        if let app = snapshot.frontmostApp {
            parts.append("Application: \(app)")
        }

        if !snapshot.ocrText.isEmpty {
            parts.append("\nVisible Text:")
            parts.append(snapshot.ocrText)
        }

        if !snapshot.elements.isEmpty {
            parts.append("\nInteractive Elements:")
            // Group by type
            let grouped = Dictionary(grouping: snapshot.elements) { $0.type }
            for type in [VisualElementType.button, .textField, .link, .dropdown, .checkbox, .radioButton, .slider, .staticText, .unknown] {
                guard let elems = grouped[type], !elems.isEmpty else { continue }
                parts.append("  \(type.displayName)s:")
                for elem in elems {
                    let enabled = elem.isEnabled ? "" : " (disabled)"
                    parts.append("    • \(elem.shortDescription)\(enabled)")
                }
            }
        }

        return parts.joined(separator: "\n")
    }

    /// Find the frontmost app name
    func getFrontmostApp() async throws -> String? {
        let result = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        tell application "System Events"
            set frontApp to first application process whose frontmost is true
            return name of frontApp
        end tell
        """])
        return result.isEmpty ? nil : result
    }

    // MARK: - OCR

    private func performOCR(at url: URL) async throws -> String {
        guard let image = NSImage(contentsOf: url),
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return ""
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = request.results?
                    .compactMap { $0 as? VNRecognizedTextObservation }
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            self.ocrQueue.async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Accessibility Element Detection

    private func detectAccessibilityElements() async throws -> [VisualElement] {
        let raw = try await scriptExecutor.run(executable: "/usr/bin/osascript", arguments: ["-e", """
        set output to ""
        tell application "System Events"
            tell (first application process whose frontmost is true)
                set uiElems to every UI element
                repeat with elem in uiElems
                    try
                        set roleStr to role of elem
                        set descStr to description of elem
                        set titleStr to title of elem
                        set enabledBool to enabled of elem
                        set pos to position of elem
                        set size to size of elem
                        set x to item 1 of pos
                        set y to item 2 of pos
                        set w to item 1 of size
                        set h to item 2 of size
                        set output to output & roleStr & "|||" & descStr & "|||" & titleStr & "|||" & enabledBool & "|||" & x & "|||" & y & "|||" & w & "|||" & h & linefeed
                    end try
                end repeat
            end tell
        end tell
        return output
        """])

        return parseAXOutput(raw)
    }

    private func parseAXOutput(_ raw: String) -> [VisualElement] {
        var elements: [VisualElement] = []
        let lines = raw.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|||")
            guard parts.count >= 8 else { continue }

            let role = parts[0].trimmingCharacters(in: .whitespaces)
            let axDescription = parts[1].trimmingCharacters(in: .whitespaces)
            let axTitle = parts[2].trimmingCharacters(in: .whitespaces)
            let enabled = parts[3].trimmingCharacters(in: .whitespaces) == "true"
            guard let x = Double(parts[4].trimmingCharacters(in: .whitespaces)),
                  let y = Double(parts[5].trimmingCharacters(in: .whitespaces)),
                  let w = Double(parts[6].trimmingCharacters(in: .whitespaces)),
                  let h = Double(parts[7].trimmingCharacters(in: .whitespaces)) else { continue }

            let label = axTitle.isEmpty ? axDescription : axTitle
            let type = VisualElementType.from(axRole: role)

            elements.append(VisualElement(
                id: UUID(),
                type: type,
                label: label,
                frame: CGRect(x: x, y: y, width: w, height: h),
                textContent: nil,
                isEnabled: enabled,
                axRole: role
            ))
        }
        return elements
    }
}
