import Foundation

final class GmailConnector: APIConnector, Connector {
    let id = "gmail"
    let name = "Gmail"
    let requiredScopes = ["https://www.googleapis.com/auth/gmail.modify"]
    var tools: [Tool] {
        [SearchMailTool(connector: self), SendMailTool(connector: self), ReadMailTool(connector: self)]
    }
}

// MARK: - Search Mail Tool

final class SearchMailTool: Tool {
    var definition = ToolDefinition(
        id: "searchMail",
        name: "Search Email",
        description: "Search Gmail messages using a query. Returns message IDs, subjects, and snippets.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Gmail search query (e.g. 'from:alice is:unread', 'subject:meeting after:2024/01/01')", type: .string, required: true),
            ToolParameter(name: "maxResults", description: "Maximum results to return (default 10)", type: .integer, required: false)
        ])
    )

    private let connector: GmailConnector

    init(connector: GmailConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        let query = input["query"]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let maxResults = input["maxResult"].flatMap(Int.init) ?? 10

        let (data, _) = try await connector.authenticatedRequest(
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(query)&maxResults=\(maxResults)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return "No messages found."
        }

        var results: [String] = []
        for msg in messages.prefix(maxResults) {
            let id = msg["id"] as? String ?? ""
            let threadId = msg["threadId"] as? String ?? ""
            let snippet = try? await getSnippet(messageId: id)
            results.append("ID: \(id)\n  Thread: \(threadId)\n  Snippet: \(snippet ?? "N/A")")
        }
        return results.isEmpty ? "No messages match '\(input["query"] ?? "")'." :
            "Found \(messages.count) messages:\n" + results.joined(separator: "\n---\n")
    }

    private func getSnippet(messageId: String) async throws -> String? {
        let (data, _) = try await connector.authenticatedRequest(
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=metadata&metadataHeaders=Subject"
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["snippet"] as? String
    }
}

// MARK: - Send Mail Tool

final class SendMailTool: Tool {
    var definition = ToolDefinition(
        id: "sendMail",
        name: "Send Email",
        description: "Send an email via Gmail.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "to", description: "Recipient email address", type: .string, required: true),
            ToolParameter(name: "subject", description: "Email subject line", type: .string, required: true),
            ToolParameter(name: "body", description: "Email body text (plain text)", type: .string, required: true)
        ])
    )

    private let connector: GmailConnector

    init(connector: GmailConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let to = input["to"], !to.isEmpty else { return "No recipient specified." }
        guard let subject = input["subject"], !subject.isEmpty else { return "No subject specified." }
        let body = input["body"] ?? ""

        let rawMessage = buildRFC822(to: to, subject: subject, body: body)
        let base64URL = rawMessage.data(using: .utf8)!.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let payload: [String: Any] = ["raw": base64URL]
        let bodyData = try JSONSerialization.data(withJSONObject: payload)

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
            body: bodyData
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Email sent but could not read response."
        }
        let messageId = json["id"] as? String ?? "unknown"
        return "✅ Email sent to \(to). Message ID: \(messageId)"
    }

    private func buildRFC822(to: String, subject: String, body: String) -> String {
        return """
        From: me
        To: \(to)
        Subject: \(subject)
        Content-Type: text/plain; charset=UTF-8

        \(body)
        """
    }
}

// MARK: - Read Mail Tool

final class ReadMailTool: Tool {
    var definition = ToolDefinition(
        id: "readMail",
        name: "Read Email",
        description: "Read the full content of a Gmail message by its ID.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "messageId", description: "The Gmail message ID to read", type: .string, required: true)
        ])
    )

    private let connector: GmailConnector

    init(connector: GmailConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let messageId = input["messageId"], !messageId.isEmpty else {
            return "No message ID provided."
        }

        let (data, _) = try await connector.authenticatedRequest(
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(messageId)?format=full"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Could not decode message."
        }

        let snippet = json["snippet"] as? String ?? ""
        let payload = json["payload"] as? [String: Any]
        let headers = payload?["headers"] as? [[String: Any]] ?? []
        let subject = headerValue(headers, name: "Subject") ?? "(no subject)"
        let from = headerValue(headers, name: "From") ?? "(unknown sender)"
        let date = headerValue(headers, name: "Date") ?? "(unknown date)"
        let body = extractBody(from: payload)

        return """
        From: \(from)
        Subject: \(subject)
        Date: \(date)
        ---
        \(body.prefix(10000))
        """
    }

    private func headerValue(_ headers: [[String: Any]], name: String) -> String? {
        headers.first { ($0["name"] as? String)?.lowercased() == name.lowercased() }?["value"] as? String
    }

    private func extractBody(from payload: [String: Any]?) -> String {
        guard let payload else { return "" }
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if (part["mimeType"] as? String) == "text/plain",
                   let body = part["body"] as? [String: Any],
                   let data = body["data"] as? String,
                   let decoded = Data(base64Encoded: data
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")) {
                    return String(data: decoded, encoding: .utf8) ?? ""
                }
                if let subParts = part["parts"] as? [[String: Any]] {
                    let sub = extractBody(from: ["parts": subParts])
                    if !sub.isEmpty { return sub }
                }
            }
        }
        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String,
           let decoded = Data(base64Encoded: data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
           let text = String(data: decoded, encoding: .utf8) {
            return text
        }
        if let snippet = payload["snippet"] as? String { return snippet }
        return ""
    }
}
