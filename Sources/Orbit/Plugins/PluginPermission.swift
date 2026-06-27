import Foundation

enum PluginPermission: String, Codable, CaseIterable, Sendable {
    case browser
    case filesystem
    case network
    case shell
    case clipboard
    case notifications
    case accessibility
    case camera
    case microphone

    var title: String {
        switch self {
        case .browser: return "Browser Automation"
        case .filesystem: return "File System Access"
        case .network: return "Network Access"
        case .shell: return "Shell Execution"
        case .clipboard: return "Clipboard Access"
        case .notifications: return "Notifications"
        case .accessibility: return "Accessibility (UI)"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        }
    }

    var icon: String {
        switch self {
        case .browser: return "globe"
        case .filesystem: return "folder"
        case .network: return "network"
        case .shell: return "terminal"
        case .clipboard: return "clipboard"
        case .notifications: return "bell"
        case .accessibility: return "figure.accessibility"
        case .camera: return "camera"
        case .microphone: return "mic"
        }
    }

    var summary: String {
        switch self {
        case .browser: return "Control web browsers and interact with web pages"
        case .filesystem: return "Read and write files on your computer"
        case .network: return "Make network requests to external services"
        case .shell: return "Execute shell commands on your system"
        case .clipboard: return "Access and modify the system clipboard"
        case .notifications: return "Send system notifications"
        case .accessibility: return "Control other apps via accessibility APIs"
        case .camera: return "Access the camera"
        case .microphone: return "Access the microphone"
        }
    }
}
