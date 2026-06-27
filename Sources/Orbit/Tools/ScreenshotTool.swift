import Foundation

final class ScreenshotTool: Tool {
    var definition = ToolDefinition(
        id: "screenshot",
        name: "Take Screenshot",
        description: "Capture a screenshot of the screen, a window, or a selected region",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "mode", description: "Capture mode: 'screen' for main display, 'window' for active window, 'selection' for drag-select region, 'all' for all displays", type: .string, required: false)
        ]),
        supportedPlatforms: ["macos"]
    )

    private let screenshotEngine = ScreenshotEngine()

    func run(input: [String: String]) async throws -> String {
        let modeRaw = input["mode"]?.lowercased() ?? ""
        let mode: ScreenshotEngine.CaptureMode = {
            if modeRaw.contains("window") || modeRaw.contains("active") || modeRaw.contains("frontmost") {
                return .activeWindow
            }
            if modeRaw.contains("all") || modeRaw.contains("every") {
                return .allDisplays
            }
            if modeRaw.contains("select") || modeRaw.contains("region") || modeRaw.contains("area") || modeRaw.contains("drag") {
                return .selection
            }
            return .mainDisplay
        }()

        let artifactsDir = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orbit/Artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: artifactsDir, withIntermediateDirectories: true)

        guard let url = screenshotEngine.captureAndSave(mode: mode, to: artifactsDir) else {
            return "Failed to capture screenshot."
        }

        return "Saved screenshot to \(url.path)"
    }
}
