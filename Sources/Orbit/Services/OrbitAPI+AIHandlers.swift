import Foundation
import Network

// MARK: - AI Service Handlers

extension OrbitAPI {
    func handleAISummarize(_ request: HTTPRequest, connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let text = body["text"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'text' field"}"#, connection: connection)
            return
        }
        let maxLength = body["maxLength"] as? Int ?? 100

        let task = Task {
            do {
                let result = try await rt.toolService.executeTool(named: "summarize", input: ["text": text, "maxLength": "\(maxLength)"])
                let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: 200, body: #"{"result":"\#(escaped)"}"#, connection: connection)
            } catch {
                sendJSON(status: 500, body: #"{"error":"\#(error.localizedDescription)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }

    func handleAIExplain(_ request: HTTPRequest, connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let text = body["text"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'text' field"}"#, connection: connection)
            return
        }
        let style = body["style"] as? String ?? "simple"

        let task = Task {
            do {
                var input: [String: String] = ["text": text]
                if style != "simple" { input["style"] = style }
                let result = try await rt.toolService.executeTool(named: "explain", input: input)
                let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: 200, body: #"{"result":"\#(escaped)"}"#, connection: connection)
            } catch {
                sendJSON(status: 500, body: #"{"error":"\#(error.localizedDescription)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }

    func handleAITranslate(_ request: HTTPRequest, connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let text = body["text"] as? String,
              let target = body["targetLanguage"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'text' or 'targetLanguage' fields"}"#, connection: connection)
            return
        }

        let task = Task {
            do {
                let result = try await rt.toolService.executeTool(named: "translate", input: ["text": text, "targetLanguage": target])
                let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: 200, body: #"{"result":"\#(escaped)"}"#, connection: connection)
            } catch {
                sendJSON(status: 500, body: #"{"error":"\#(error.localizedDescription)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }

    func handleAIRefactor(_ request: HTTPRequest, connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let code = body["code"] as? String,
              let instructions = body["instructions"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'code' or 'instructions' fields"}"#, connection: connection)
            return
        }

        let task = Task {
            do {
                let result = try await rt.toolService.executeTool(named: "refactor", input: ["code": code, "instructions": instructions])
                let escaped = result.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: 200, body: #"{"result":"\#(escaped)"}"#, connection: connection)
            } catch {
                sendJSON(status: 500, body: #"{"error":"\#(error.localizedDescription)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }

    func handleGetContext(_ connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        let activeConvId = rt.conversationService.activeConversationId?.uuidString ?? ""
        let convCount = rt.conversationService.conversations.count
        let wsCount = rt.workspaceService.workspaces.count

        let context: [String: Any] = [
            "activeConversationId": activeConvId,
            "conversationCount": convCount,
            "workspaceCount": wsCount
        ]

        if let data = try? JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted]),
           let body = String(data: data, encoding: .utf8) {
            sendJSON(status: 200, body: body, connection: connection)
        } else {
            sendJSON(status: 200, body: "{}", connection: connection)
        }
    }
}
