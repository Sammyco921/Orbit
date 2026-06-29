import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "cdp")

actor CDPConnection {
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextId = 1
    private var isConnected = false

    func connect(to url: URL) async throws {
        let session = URLSession(configuration: .default)
        self.session = session
        let ws = session.webSocketTask(with: url)
        webSocket = ws
        ws.resume()
        isConnected = true
        listen()
    }

    func disconnect() {
        isConnected = false
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session = nil
        let continuations = pendingRequests
        pendingRequests = [:]
        for (_, cont) in continuations {
            cont.resume(throwing: CDPError.connectionClosed)
        }
    }

    @discardableResult
    func send(method: String, params: [String: Any]? = nil) async throws -> [String: Any] {
        guard isConnected, let ws = webSocket else {
            throw CDPError.connectionClosed
        }
        let id = nextId
        nextId += 1

        let request = CDPRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        try await ws.send(.data(data))

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
    }

    @discardableResult
    func send(method: String, params: [String: Any]? = nil, timeout: TimeInterval) async throws -> [String: Any] {
        return try await withThrowingTimeout(timeout) {
            try await self.send(method: method, params: params)
        }
    }

    private func listen() {
        guard isConnected, let ws = webSocket else { return }
        ws.receive { [weak self] result in
            Task { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    await handleMessage(message)
                    await listen()
                case .failure(let error):
                    log.error("WebSocket receive error: \(error.localizedDescription)")
                    let continuations = await self.pendingRequests
                    for (_, cont) in continuations {
                        cont.resume(throwing: error)
                    }
                    await disconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            handleData(data)
        case .string(let string):
            guard let data = string.data(using: .utf8) else { return }
            handleData(data)
        @unknown default:
            break
        }
    }

    private func handleData(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(CDPResponse.self, from: data)

            if let id = response.id {
                if let error = response.error {
                    pendingRequests[id]?.resume(throwing: error)
                } else {
                    pendingRequests[id]?.resume(returning: response.result ?? [:])
                }
                pendingRequests[id] = nil
            } else if response.method != nil {
                handleEvent(response)
            }
        } catch {
            log.error("Failed to decode CDP message: \(error.localizedDescription)")
        }
    }

    private var eventHandlers: [String: (CDPResponse) -> Void] = [:]

    func onEvent(_ method: String, handler: @escaping (CDPResponse) -> Void) {
        eventHandlers[method] = handler
    }

    func clearEventHandlers() {
        eventHandlers = [:]
    }

    private func handleEvent(_ event: CDPResponse) {
        guard let method = event.method else { return }
        if let handler = eventHandlers[method] {
            handler(event)
        }
    }
}

// MARK: - Errors

enum CDPError: Error, LocalizedError {
    case connectionClosed
    case commandFailed(String)
    case timeout
    case chromeNotRunning

    var errorDescription: String? {
        switch self {
        case .connectionClosed: return "CDP connection closed"
        case .commandFailed(let msg): return "CDP command failed: \(msg)"
        case .timeout: return "CDP command timed out"
        case .chromeNotRunning: return "Chrome is not running"
        }
    }
}

// MARK: - Timeout helper

private func withThrowingTimeout<T>(_ seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CDPError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
