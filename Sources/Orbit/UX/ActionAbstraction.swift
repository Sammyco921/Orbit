import Foundation

// MARK: - Tool Abstraction Layer (Rule 6)
// Maps internal tool IDs to human-readable Orbit actions.
// Users NEVER see tool/sdk internals — only "Orbit actions".

struct ActionAbstraction {

    /// Human-readable description of what Orbit is doing
    static func describeAction(toolID: String, input: [String: String]) -> String {
        switch toolID {
        case "screenshot":
            return "Capturing screen..."
        case "terminalRun":
            let cmd = input["command"] ?? ""
            let summary = cmd.prefix(60)
            return "Running command: \(summary)"
        case "systemInfo":
            return "Gathering system information..."
        case "openApplication":
            let app = input["name"] ?? input["application"] ?? ""
            return "Opening \(app)..."
        case "fileWrite", "fileWriteTool":
            let path = input["path"] ?? input["filePath"] ?? ""
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "Writing file: \(name)"
        case "readFile", "fileRead":
            let path = input["path"] ?? input["filePath"] ?? ""
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "Reading file: \(name)"
        case "listDirectory":
            let path = input["path"] ?? input["directory"] ?? ""
            return "Listing directory: \(path)"
        case "clipboard":
            return "Accessing clipboard..."
        case "openURL":
            let url = input["url"] ?? ""
            return "Opening URL: \(url)"
        case "gitStatus":
            return "Checking git status..."
        case "gitDiff":
            return "Checking git changes..."
        case "gitLog":
            return "Reading git history..."
        case "gitCommit":
            return "Committing changes..."
        case "gitPush":
            return "Pushing to remote..."
        case "gitPull":
            return "Pulling from remote..."
        case "calendarEvent", "calendar":
            return "Creating calendar event..."
        case "contactLookup", "contacts":
            return "Looking up contacts..."
        case "musicControl", "music":
            return "Controlling music..."
        case "brightnessControl", "brightness":
            return "Adjusting brightness..."
        case "notificationSend":
            return "Sending notification..."
        case "speak":
            return "Speaking output..."
        case "diskUsage":
            return "Checking disk usage..."
        case "batteryStatus":
            return "Checking battery status..."
        case "networkInfo":
            return "Checking network info..."
        case "dateTime":
            return "Checking date and time..."
        case "finderSearch":
            return "Searching files..."
        case "processes":
            return "Listing running processes..."
        case "volumeControl", "volume":
            return "Adjusting volume..."
        case "keyboardType":
            return "Typing text..."
        case "mouseClick":
            return "Clicking at position..."
        case "frontmostApp":
            return "Checking active application..."
        case "killApp":
            return "Stopping application..."
        case "dockAction":
            return "Performing dock action..."
        case "accessibilityAction":
            return "Performing accessibility action..."
        case "fileDelete":
            return "Deleting file..."
        case "fileMove":
            return "Moving file..."
        case "createFolder":
            return "Creating folder..."
        case "echo":
            return "Processing request..."
        case "browserNavigate", "browser.navigate":
            return "Navigating in browser..."
        case "browserClick", "browser.click":
            return "Clicking in browser..."
        case "browserType", "browser.type":
            return "Typing in browser..."
        case "browserExtract", "browser.extract":
            return "Reading page content..."
        case "browserScreenshot", "browser.screenshot":
            return "Capturing browser page..."
        case "screenDescribe":
            return "Analyzing screen contents..."
        case "visualClick":
            return "Clicking on screen element..."
        case "visualType":
            return "Typing into field..."
        default:
            return "Running action..."
        }
    }

    /// What Orbit expects to achieve (high-level)
    static func expectedOutput(for toolID: String, input: [String: String]) -> String {
        switch toolID {
        case "screenshot":
            return "Screen capture image"
        case "terminalRun":
            return "Command output"
        case "systemInfo":
            return "System hardware and software details"
        case "openApplication":
            return "Application launched"
        case "fileWrite", "fileWriteTool":
            return "File written to disk"
        case "readFile", "fileRead":
            return "File contents"
        case "listDirectory":
            return "List of files and folders"
        case "clipboard":
            return "Clipboard contents"
        case "openURL":
            return "Webpage opened"
        case "gitStatus":
            return "Working tree status"
        case "gitDiff":
            return "Uncommitted changes"
        case "gitLog":
            return "Commit history"
        case "gitCommit":
            return "New commit created"
        case "gitPush":
            return "Changes pushed to remote"
        case "gitPull":
            return "Latest changes pulled"
        case "calendarEvent", "calendar":
            return "Event created in calendar"
        case "contactLookup", "contacts":
            return "Contact information"
        case "musicControl", "music":
            return "Music state changed"
        case "brightnessControl", "brightness":
            return "Display brightness adjusted"
        case "notificationSend":
            return "Notification sent"
        case "speak":
            return "Text spoken aloud"
        case "diskUsage":
            return "Disk usage information"
        case "batteryStatus":
            return "Battery health and charge"
        case "networkInfo":
            return "Network configuration"
        case "dateTime":
            return "Current date and time"
        case "finderSearch":
            return "Search results from Finder"
        case "processes":
            return "Running processes"
        case "volumeControl", "volume":
            return "Volume level changed"
        case "keyboardType":
            return "Text typed"
        case "frontmostApp":
            return "Active application name"
        case "killApp":
            return "Application terminated"
        case "fileDelete":
            return "File moved to trash"
        case "fileMove":
            return "File moved to new location"
        case "createFolder":
            return "New folder created"
        case "echo":
            return "Processed response"
        case "browserNavigate", "browser.navigate":
            return "Page loaded"
        case "browserClick", "browser.click":
            return "Element clicked"
        case "browserType", "browser.type":
            return "Text entered"
        case "browserExtract", "browser.extract":
            return "Page content extracted"
        case "browserScreenshot", "browser.screenshot":
            return "Page screenshot captured"
        case "screenDescribe":
            return "Screen description"
        case "visualClick":
            return "Element clicked via screen analysis"
        case "visualType":
            return "Text typed into field"
        default:
            return "Action result"
        }
    }

    /// Summary of what was done (for final summary rule 7)
    static func summaryOfAction(toolID: String, output: String) -> String {
        let preview = String(output.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        let actionName = describeAction(toolID: toolID, input: [:])
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespaces)
        if preview.isEmpty {
            return "\(actionName) completed"
        }
        return "\(actionName): \(preview)"
    }
}
