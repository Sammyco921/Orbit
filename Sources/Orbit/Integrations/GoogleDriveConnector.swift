import Foundation

final class GoogleDriveConnector: APIConnector, Connector {
    let id = "drive"
    let name = "Google Drive"
    let requiredScopes = ["https://www.googleapis.com/auth/drive.readonly"]
    var tools: [Tool] {
        [FindDriveFileTool(connector: self), ReadDriveFileTool(connector: self)]
    }
}

// MARK: - Find File Tool

final class FindDriveFileTool: Tool {
    var definition = ToolDefinition(
        id: "findDriveFile",
        name: "Find Drive File",
        description: "Search for files in Google Drive by name or query.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "query", description: "Search query (e.g. 'invoice 2024', 'budget spreadsheet')", type: .string, required: true),
            ToolParameter(name: "maxResults", description: "Maximum results (default 5)", type: .integer, required: false)
        ])
    )

    private let connector: GoogleDriveConnector

    init(connector: GoogleDriveConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        let query = input["query"]?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let maxResults = input["maxResult"].flatMap(Int.init) ?? 5

        let (data, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/drive/v3/files?q=name contains '\(query)'&pageSize=\(maxResults)&fields=files(id,name,mimeType,size,modifiedTime,webViewLink)"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            return "No files found."
        }

        if files.isEmpty { return "No files match '\(input["query"] ?? "")'." }

        var results: [String] = []
        for file in files {
            let name = file["name"] as? String ?? ""
            let mimeType = file["mimeType"] as? String ?? ""
            let modified = file["modifiedTime"] as? String ?? ""
            let link = file["webViewLink"] as? String ?? ""
            results.append("\(name) (\(mimeType))\n  Modified: \(modified.prefix(10))\n  \(link)")
        }
        return results.joined(separator: "\n---\n")
    }
}

// MARK: - Read File Tool

final class ReadDriveFileTool: Tool {
    var definition = ToolDefinition(
        id: "readDriveFile",
        name: "Read Drive File",
        description: "Read the contents of a Google Drive file by its ID (supports Google Docs, text files).",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "fileId", description: "The file ID from findDriveFile", type: .string, required: true)
        ])
    )

    private let connector: GoogleDriveConnector

    init(connector: GoogleDriveConnector) { self.connector = connector }

    func run(input: [String: String]) async throws -> String {
        guard let fileId = input["fileId"], !fileId.isEmpty else { return "No file ID provided." }

        let (metaData, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/drive/v3/files/\(fileId)?fields=mimeType,name"
        )

        guard let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: Any] else {
            return "Could not fetch file metadata."
        }

        let mimeType = meta["mimeType"] as? String ?? ""
        let name = meta["name"] as? String ?? ""

        if mimeType == "application/vnd.google-apps.document" {
            let (data, _) = try await connector.authenticatedRequest(
                url: "https://docs.googleapis.com/v1/documents/\(fileId)/export?mimeType=text/plain"
            )
            let text = String(data: data, encoding: .utf8) ?? ""
            return "File: \(name)\n\n\(text.prefix(10000))"
        }

        let (data, _) = try await connector.authenticatedRequest(
            url: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media"
        )
        let text = String(data: data, encoding: .utf8) ?? "(binary content)"
        return "File: \(name) (\(mimeType))\n\n\(text.prefix(10000))"
    }
}
