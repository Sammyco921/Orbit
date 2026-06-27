import Foundation

final class SlackConnector: APIConnector, Connector {
    let id = "slack"
    let name = "Slack"
    let requiredScopes = ["channels:read", "chat:write", "users:read"]
    var tools: [Tool] {
        [SendSlackMessageTool(connector: self), ListSlackChannelsTool(connector: self)]
    }

    var baseURL: String { "https://slack.com/api" }
}

// MARK: - Send Slack Message Tool

final class SendSlackMessageTool: Tool {
    var definition = ToolDefinition(
        id: "sendSlackMessage",
        name: "Send Slack Message",
        description: "Send a message to a Slack channel.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "channel", description: "Channel name (e.g. '#general', 'C12345') or user ID", type: .string, required: true),
            ToolParameter(name: "text", description: "Message text", type: .string, required: true)
        ])
    )

    private let connector: SlackConnector

    init(connector: SlackConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let channel = input["channel"], !channel.isEmpty else { return "No channel specified." }
        guard let text = input["text"], !text.isEmpty else { return "No message text specified." }

        let body: [String: Any] = ["channel": channel, "text": text]

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "\(connector.baseURL)/chat.postMessage",
            body: connector.jsonBody(body)
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Message sent but could not parse response."
        }

        if json["ok"] as? Bool == true {
            let ts = json["ts"] as? String ?? ""
            return "✅ Message sent to \(channel) (timestamp: \(ts))"
        }
        let error = json["error"] as? String ?? "unknown"
        return "Slack API error: \(error)"
    }
}

// MARK: - List Slack Channels Tool

final class ListSlackChannelsTool: Tool {
    var definition = ToolDefinition(
        id: "listSlackChannels",
        name: "List Slack Channels",
        description: "List public channels in the Slack workspace.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "limit", description: "Maximum channels to return (default 20)", type: .integer, required: false)
        ])
    )

    private let connector: SlackConnector

    init(connector: SlackConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        let limit = input["limi"].flatMap(Int.init) ?? 20

        let (data, _) = try await connector.authenticatedRequest(
            url: "\(connector.baseURL)/conversations.list?types=public_channel&limit=\(limit)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channels = json["channels"] as? [[String: Any]] else {
            return "Could not parse channel list."
        }

        if channels.isEmpty { return "No channels found." }

        var results: [String] = []
        for ch in channels {
            let name = ch["name"] as? String ?? ""
            let memberCount = ch["num_members"] as? Int ?? 0
            let topic = (ch["topic"] as? [String: Any])?["value"] as? String ?? ""
            results.append("#\(name) (\(memberCount) members)\n  Topic: \(topic.prefix(100))")
        }
        return results.joined(separator: "\n---\n")
    }
}
