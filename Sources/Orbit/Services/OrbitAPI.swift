import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "api")

let crlf = "\r\n"

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    var bodyString: String? { String(data: body, encoding: .utf8) }
    var jsonBody: Any? {
        guard let str = bodyString, let data = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: crlf)
        guard lines.count >= 1 else { return nil }

        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else { return nil }

        let method = requestLine[0]
        let path = requestLine[1]

        var headers: [String: String] = [:]
        var i = 1
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty { i += 1; break }
            let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
            }
            i += 1
        }

        let bodyData: Data
        if let contentLength = headers["content-length"], let length = Int(contentLength), length > 0 {
            let bodyText = lines[i...].joined(separator: crlf)
            bodyData = Data(bodyText.utf8)
        } else {
            bodyData = Data()
        }

        return HTTPRequest(method: method.uppercased(), path: path, headers: headers, body: bodyData)
    }
}

final class OrbitAPI {
    weak var runtime: OrbitRuntime?
    private var listener: NWListener?
    private(set) var apiKey: String = ""
    private(set) var port: UInt16 = 0
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private let rateLimiter = RateLimiter(maxRequestsPerSecond: 30, label: "OrbitAPI")

    func trackTask(_ task: Task<Void, Never>) {
        let id = UUID()
        activeTasks[id] = task
        Task {
            await task.value
            activeTasks[id] = nil
        }
    }

    func configure(runtime: OrbitRuntime?, apiKey: String) {
        self.runtime = runtime
        self.apiKey = apiKey
    }

    func start(port: UInt16 = 0) throws {
        let params = NWParameters(tls: nil, tcp: .init())
        params.allowLocalEndpointReuse = true

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw OrbitError.invalidInput("Invalid port number: \(port)")
        }
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let actualPort = listener.port?.rawValue {
                self?.port = actualPort
                log.notice("API server started on 127.0.0.1:\(actualPort)")
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        listener.start(queue: DispatchQueue.global())
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
    }

    func waitForReady(timeout: TimeInterval = 5) async -> Bool {
        let deadline = CFAbsoluteTimeGetCurrent() + timeout
        while port == 0 && CFAbsoluteTimeGetCurrent() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return port != 0
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: DispatchQueue.global())
        readRequest(connection)
    }

    private func readRequest(_ connection: NWConnection, buffer: Data = Data()) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var currentBuffer = buffer
            if let data = data { currentBuffer.append(data) }

            if let request = HTTPRequest.parse(currentBuffer) {
                self.dispatch(request, connection: connection)
                return
            }

            if isComplete || error != nil {
                if let error {
                    log.warning("Connection error: \(error.localizedDescription)")
                }
                connection.cancel()
            } else {
                self.readRequest(connection, buffer: currentBuffer)
            }
        }
    }

    private func dispatch(_ request: HTTPRequest, connection: NWConnection) {
        guard authenticate(request) else {
            sendJSON(status: 401, body: #"{"error":"Unauthorized"}"#, connection: connection)
            return
        }

        if !rateLimiter.acquire() {
            sendJSON(status: 429, body: #"{"error":"Rate limit exceeded"}"#, connection: connection)
            return
        }

        switch (request.method, request.path) {
        case ("POST", "/api/tools/call"):
            handleCallTool(request, connection: connection)
        case ("POST", "/api/agent/execute"):
            handleAgentExecute(request, connection: connection)
        case ("GET", "/api/conversations"):
            handleGetConversations(connection)
        case ("POST", "/api/conversations"):
            handleCreateConversation(request, connection: connection)
        case ("GET", "/api/memory/search"):
            handleMemorySearch(request, connection: connection)
        case ("POST", "/api/ai/summarize"):
            handleAISummarize(request, connection: connection)
        case ("POST", "/api/ai/explain"):
            handleAIExplain(request, connection: connection)
        case ("POST", "/api/ai/translate"):
            handleAITranslate(request, connection: connection)
        case ("POST", "/api/ai/refactor"):
            handleAIRefactor(request, connection: connection)
        case ("GET", "/api/context"):
            handleGetContext(connection)
        case ("GET", "/api/executions"):
            handleGetExecutions(connection)
        case ("GET", "/api/executions/sessions"):
            handleGetExecutionSessions(connection)
        case ("GET", "/api/health"):
            sendJSON(status: 200, body: #"{"status":"ok"}"#, connection: connection)
        default:
            sendJSON(status: 404, body: #"{"error":"Not found"}"#, connection: connection)
        }
    }

    // MARK: - Auth

    private func authenticate(_ request: HTTPRequest) -> Bool {
        guard let auth = request.headers["authorization"] else { return false }
        guard !apiKey.isEmpty else { return false }
        return auth == "Bearer \(apiKey)"
    }
}
