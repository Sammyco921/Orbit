import Foundation

final class NotificationSendTool: Tool {
    var definition = ToolDefinition(
        id: "notificationSend",
        name: "Send Notification",
        description: "Send a macOS notification",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "message", description: "The notification message text", type: .string, required: true),
            ToolParameter(name: "title", description: "Optional custom title (default: Orbit Action)", type: .string, required: false)
        ])
    )

    func run(input: [String: String]) async throws -> String {
        guard let message = input["message"], !message.isEmpty else {
            return "What should the notification say?"
        }
        let title = input["title"] ?? "Orbit Action"

        if Platform.current == .linux {
            try await LinuxCommands.sendNotification(title: title, body: message)
            return "Notification sent: \(message)"
        }

        NotificationManager.shared.send(title: title, body: message)
        return "Notification sent: \(message)"
    }
}
