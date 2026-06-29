import Foundation

final class CalendarConnector: APIConnector, Connector {
    let id = "calendar"
    let name = "Google Calendar"
    let requiredScopes = ["https://www.googleapis.com/auth/calendar.events"]
    var tools: [Tool] {
        [CreateCalendarEventTool(connector: self), ListCalendarEventsTool(connector: self)]
    }
}

// MARK: - Create Event Tool

final class CreateCalendarEventTool: Tool {
    var definition = ToolDefinition(
        id: "createCalendarEvent",
        name: "Create Calendar Event",
        description: "Create an event in Google Calendar.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "summary", description: "Event title", type: .string, required: true),
            ToolParameter(name: "date", description: "Date and time (ISO 8601, e.g. '2026-06-25T14:00:00')", type: .string, required: true),
            ToolParameter(name: "durationMinutes", description: "Duration in minutes (default 60)", type: .integer, required: false),
            ToolParameter(name: "description", description: "Event description", type: .string, required: false),
            ToolParameter(name: "attendees", description: "Comma-separated email addresses", type: .string, required: false)
        ])
    )

    private let connector: CalendarConnector

    init(connector: CalendarConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let summary = input["summary"], !summary.isEmpty else { return "No summary specified." }
        guard let startStr = input["date"], !startStr.isEmpty else { return "No date specified." }
        let duration = (input["durationMinute"]).flatMap(Double.init) ?? 60
        let endStr = ISO8601DateFormatter().date(from: startStr).map {
            ISO8601DateFormatter().string(from: $0.addingTimeInterval(duration * 60))
        } ?? startStr

        var event: [String: Any] = [
            "summary": summary,
            "start": ["dateTime": startStr, "timeZone": "America/New_York"],
            "end": ["dateTime": endStr, "timeZone": "America/New_York"]
        ]

        if let desc = input["description"] { event["description"] = desc }
        if let attendeesStr = input["attendees"] {
            event["attendees"] = attendeesStr.components(separatedBy: ",").map {
                ["email": $0.trimmingCharacters(in: .whitespaces)]
            }
        }

        let (data, _) = try await connector.authenticatedRequest(
            method: "POST",
            url: "https://www.googleapis.com/calendar/v3/calendars/primary/events",
            body: connector.jsonBody(event)
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Event created but could not parse response."
        }

        let htmlLink = json["htmlLink"] as? String ?? ""
        let eventId = json["id"] as? String ?? ""
        return "✅ Event created: \(summary)\n\(htmlLink)\nID: \(eventId)"
    }
}

// MARK: - List Events Tool

final class ListCalendarEventsTool: Tool {
    var definition = ToolDefinition(
        id: "listCalendarEvents",
        name: "List Calendar Events",
        description: "List upcoming events from Google Calendar.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "maxResults", description: "Maximum events to return (default 10)", type: .integer, required: false),
            ToolParameter(name: "timeMin", description: "Start of time range (ISO 8601, defaults to now)", type: .string, required: false)
        ])
    )

    private let connector: CalendarConnector

    init(connector: CalendarConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        let maxResults = input["maxResult"].flatMap(Int.init) ?? 10
        let timeMin = input["timeMin"] ?? ISO8601DateFormatter().string(from: Date())

        let (data, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=\(timeMin.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? timeMin)&maxResults=\(maxResults)&orderBy=startTime&singleEvents=true"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return "No events found."
        }

        if items.isEmpty { return "No upcoming events." }

        var results: [String] = []
        for event in items {
            let summary = event["summary"] as? String ?? "(no title)"
            let start = (event["start"] as? [String: Any])?["dateTime"] as? String
                ?? (event["start"] as? [String: Any])?["date"] as? String
                ?? ""
            let link = event["htmlLink"] as? String ?? ""
            results.append("\(summary)\n  \(start.prefix(16).replacingOccurrences(of: "T", with: " "))\n  \(link)")
        }
        return results.joined(separator: "\n---\n")
    }
}
