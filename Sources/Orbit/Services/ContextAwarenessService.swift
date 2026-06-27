import AppKit
import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "context-awareness")

/// Tracks what the user is currently doing — frontmost app, active URL, document
final class ContextAwarenessService {

    deinit {
        timer?.invalidate()
    }

    struct Context: Codable, CustomStringConvertible {
        var frontmostApp: String = ""
        var frontmostWindowTitle: String = ""
        var activeURL: String?
        var activeFilePath: String?
        var lastActiveAt = Date()

        var description: String {
            var parts = ["App: \(frontmostApp)", "Window: \(frontmostWindowTitle)"]
            if let url = activeURL { parts.append("URL: \(url)") }
            if let file = activeFilePath { parts.append("File: \(file)") }
            return parts.joined(separator: ", ")
        }
    }

    @Published private(set) var currentContext = Context()

    private var timer: Timer?

    func start() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.update()
        }
        log.notice("Context awareness started")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        log.notice("Context awareness stopped")
    }

    private func update() {
        let apps = NSWorkspace.shared.runningApplications
        guard let frontApp = apps.first(where: { $0.isActive }) else { return }

        var ctx = Context()
        ctx.frontmostApp = frontApp.localizedName ?? frontApp.bundleIdentifier ?? "Unknown"
        ctx.lastActiveAt = Date()

        // Window title via AppleScript
        ctx.frontmostWindowTitle = getFrontmostWindowTitle()

        // Try to detect browser URL
        let bundleID = frontApp.bundleIdentifier ?? ""
        ctx.activeURL = detectActiveURL(bundleID: bundleID)

        // Try to detect active file
        ctx.activeFilePath = detectActiveFile(bundleID: bundleID)

        currentContext = ctx
        log.debug("Context: \(ctx.description)")
    }

    private func getFrontmostWindowTitle() -> String {
        guard let script = NSAppleScript(source: """
            tell application "System Events"
                set frontApp to first application process whose frontmost is true
                set appName to name of frontApp
                tell process appName
                    if (count of windows) > 0 then
                        set winTitle to name of front window
                        return winTitle
                    end if
                end tell
            end tell
            return ""
        """) else { return "" }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return result.stringValue ?? ""
    }

    private func detectActiveURL(bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.Safari":
            return runJavaScriptAppleScript("""
                tell application "Safari"
                    return URL of current tab of front window
                end tell
            """)
        case "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac":
            let appName: String
            switch bundleID {
            case "com.google.Chrome": appName = "Google Chrome"
            case "com.brave.Browser": appName = "Brave Browser"
            case "com.microsoft.edgemac": appName = "Microsoft Edge"
            default: return nil
            }
            return runJavaScriptAppleScript("""
                tell application "\(appName)"
                    return URL of active tab of front window
                end tell
            """)
        default:
            return nil
        }
    }

    private func detectActiveFile(bundleID: String) -> String? {
        switch bundleID {
        case "com.apple.finder":
            return runJavaScriptAppleScript("""
                tell application "Finder"
                    if (count of windows) > 0 then
                        set targetPath to POSIX path of (target of front window as alias)
                        return targetPath
                    end if
                end tell
                return ""
            """)
        case "com.apple.Xcode":
            return runJavaScriptAppleScript("""
                tell application "Xcode"
                    if (count of documents) > 0 then
                        set docPath to path of first document whose name is not missing value
                        return docPath
                    end if
                end tell
                return ""
            """)
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            return runJavaScriptAppleScript("""
                tell application "System Events"
                    tell process "\(bundleID.contains("Insiders") ? "Code - Insiders" : "Code")"
                        if (count of windows) > 0 then
                            set winTitle to name of front window
                            return winTitle
                        end if
                    end tell
                end tell
                return ""
            """)
        default:
            return nil
        }
    }

    private func runJavaScriptAppleScript(_ source: String) -> String? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        if error != nil { return nil }
        return result?.stringValue
    }
}
