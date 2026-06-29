import Foundation
import Network

// MARK: - Route Handlers

extension OrbitAPI {
    func handleCallTool(_ request: HTTPRequest, connection: NWConnection) {
        guard runtime != nil else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let toolName = body["name"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'name' field"}"#, connection: connection)
            return
        }

        let input = body["input"] as? [String: String] ?? [:]

        let task = Task { [weak self] in
            guard let self, let rt = runtime else { return }
            do {
                let result = try await rt.toolService.executeTool(named: toolName, input: input, approvalMode: .throwOnApproval)
                let resp = #"{"result":"\#(result.replacingOccurrences(of: "\"", with: "\\\""))"}"#
                sendJSON(status: 200, body: resp, connection: connection)
            } catch let error as OrbitError {
                let status: Int
                switch error {
                case .toolNotFound: status = 404
                case .toolRequiresApproval: status = 403
                default: status = 500
                }
                let msg = error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: status, body: #"{"error":"\#(msg)"}"#, connection: connection)
            } catch {
                let msg = error.localizedDescription.replacingOccurrences(of: "\"", with: "\\\"")
                sendJSON(status: 500, body: #"{"error":"\#(msg)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }

    func handleAgentExecute(_ request: HTTPRequest, connection: NWConnection) {
        guard runtime != nil else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let body = request.jsonBody as? [String: Any],
              let goal = body["goal"] as? String else {
            sendJSON(status: 400, body: #"{"error":"Missing 'goal' field"}"#, connection: connection)
            return
        }

        sendSSEHeaders(connection)

        let task = Task { [weak self] in
            guard let self, let rt = runtime else { return }
            let stream = rt.workflowEngine.executeReAct(
                goalDescription: goal,
                maxSteps: 25,
                contextMessages: [],
                llm: rt.llmService.currentProvider(),
                tools: rt.toolService.toolRegistry,
                parameters: ModelParameters(),
                checkpointManager: nil,
                executionId: UUID().uuidString,
                conversationId: nil,
                approvalMode: .throwOnApproval
            )

            for await event in stream {
                if Task.isCancelled || connection.state != .ready { break }
                switch event {
                case .thought(let text):
                    sendSSEEvent(type: "thought", data: text, connection: connection)
                case .toolExecution(let name, let input):
                    sendSSEEvent(type: "tool", data: "\(name): \(input)", connection: connection)
                case .toolResult(_, let output):
                    sendSSEEvent(type: "result", data: output, connection: connection)
                case .error(let error):
                    sendSSEEvent(type: "error", data: error, connection: connection)
                case .completed(let summary):
                    sendSSEEvent(type: "completed", data: summary, connection: connection)
                }
            }
            sendSSEEvent(type: "done", data: "", connection: connection)
            connection.cancel()
        }
        trackTask(task)
    }

    func handleGetConversations(_ connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        let convs = rt.conversationService.conversations.map { c in
            [
                "id": c.id.uuidString,
                "title": c.title,
                "workspaceId": c.workspaceId?.uuidString ?? "",
                "createdAt": c.createdAt.timeIntervalSince1970
            ] as [String: Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: convs, options: [.prettyPrinted]),
           let body = String(data: data, encoding: .utf8) {
            sendJSON(status: 200, body: body, connection: connection)
        } else {
            sendJSON(status: 200, body: "[]", connection: connection)
        }
    }

    func handleCreateConversation(_ request: HTTPRequest, connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        let body = request.jsonBody as? [String: Any]
        let title = body?["title"] as? String ?? "API Conversation"
        rt.conversationService.createConversation(workspaceId: nil)
        if let conv = rt.conversationService.conversations.last {
            sendJSON(status: 201, body: #"{"id":"\#(conv.id.uuidString)","title":"\#(title)","createdAt":\#(conv.createdAt.timeIntervalSince1970)}"#, connection: connection)
        } else {
            sendJSON(status: 500, body: #"{"error":"Failed to create conversation"}"#, connection: connection)
        }
    }

    func handleGetExecutions(_ connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        let entries = rt.auditService.recent(limit: 100)
        let json = entries.map { entry in
            [
                "id": entry.id,
                "sessionId": entry.sessionId,
                "toolName": entry.toolName,
                "outcome": entry.outcome,
                "errorDetail": entry.errorDetail ?? "",
                "durationMs": entry.durationMs,
                "createdAt": entry.createdAt.timeIntervalSince1970,
            ] as [String: Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let body = String(data: data, encoding: .utf8) {
            sendJSON(status: 200, body: body, connection: connection)
        } else {
            sendJSON(status: 500, body: #"{"error":"Failed to serialize"}"#, connection: connection)
        }
    }

    func handleGetExecutionSessions(_ connection: NWConnection) {
        guard let rt = runtime else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        let sessions = rt.auditService.sessionsList(limit: 50)
        let json = sessions.map { s in
            [
                "sessionId": s.sessionId,
                "count": s.count,
                "firstTool": s.firstTool,
                "lastTime": s.lastTime.timeIntervalSince1970,
            ] as [String: Any]
        }
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]),
           let body = String(data: data, encoding: .utf8) {
            sendJSON(status: 200, body: body, connection: connection)
        } else {
            sendJSON(status: 500, body: #"{"error":"Failed to serialize"}"#, connection: connection)
        }
    }

    func handleMemorySearch(_ request: HTTPRequest, connection: NWConnection) {
        guard runtime != nil else { return sendJSON(status: 503, body: #"{"error":"Runtime not available"}"#, connection: connection) }
        guard let components = URLComponents(string: "http://localhost\(request.path)")?.queryItems,
              let query = components.first(where: { $0.name == "q" })?.value else {
            sendJSON(status: 400, body: #"{"error":"Missing 'q' query parameter"}"#, connection: connection)
            return
        }

        let task = Task { [weak self] in
            guard let self, let rt = runtime else { return }
            guard let store = rt.memoryService.memoryStore else {
                sendJSON(status: 500, body: #"{"error":"Memory not available"}"#, connection: connection)
                return
            }
            do {
                let items = try store.searchGlobalItems(limit: 20)
                let filtered = query.isEmpty ? items : items.filter { $0.content.localizedCaseInsensitiveContains(query) }
                let results = filtered.map { item in
                    [
                        "id": item.id,
                        "content": item.content,
                        "type": item.type
                    ] as [String: Any]
                }
                if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted]),
                   let body = String(data: data, encoding: .utf8) {
                    sendJSON(status: 200, body: body, connection: connection)
                } else {
                    sendJSON(status: 200, body: "[]", connection: connection)
                }
            } catch {
                sendJSON(status: 500, body: #"{"error":"\#(error.localizedDescription)"}"#, connection: connection)
            }
        }
        trackTask(task)
    }
}
