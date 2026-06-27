import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "oauth-server")

actor OAuthRedirectServer {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    func start(port: UInt16) async throws -> Int {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                log.error("OAuth server listener failed: \(error.localizedDescription)")
            }
        }

        return try await withCheckedThrowingContinuation { (outerCont: CheckedContinuation<Int, Error>) in
            listener.serviceRegistrationUpdateHandler = { change in
                if case .add(let endpoint) = change {
                    if case .hostPort(_, let actualPort) = endpoint {
                        outerCont.resume(returning: Int(actualPort.rawValue))
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                conn.stateUpdateHandler = { state in
                    if state == .ready {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                            if let error {
                                log.error("OAuth server receive error: \(error.localizedDescription)")
                                conn.cancel()
                                return
                            }

                            if let data, let request = String(data: data, encoding: .utf8) {
                                Task { await self?.handle(request, from: conn) }
                            } else if isComplete {
                                conn.cancel()
                            }
                        }
                    }
                }
                conn.start(queue: .global())
            }

            listener.start(queue: .global())
        }
    }

    func waitForCallback() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func cancel() {
        listener?.cancel()
        listener = nil
        continuation?.resume(throwing: OAuthError.redirectServerFailed("Server cancelled"))
        continuation = nil
    }

    private func handle(_ request: String, from connection: NWConnection) {
        let url = parseRedirectURL(from: request)

        guard let url else {
            sendResponse(connection, statusCode: 400, body: "Invalid request")
            connection.cancel()
            return
        }

        sendResponse(connection, statusCode: 200, body: """
        <!DOCTYPE html>
        <html>
        <head><title>Orbit — Authorized</title></head>
        <body style="font-family: -apple-system; display: flex; justify-content: center; align-items: center; height: 100vh;">
            <div style="text-align: center;">
                <h1>✅ Authorized</h1>
                <p>You can close this tab and return to Orbit.</p>
            </div>
        </body>
        </html>
        """)
        connection.cancel()

        continuation?.resume(returning: url)
        continuation = nil
    }

    private nonisolated func parseRedirectURL(from request: String) -> String? {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        let pathAndQuery = components[1]
        return "http://127.0.0.1\(pathAndQuery)"
    }

    private nonisolated func sendResponse(_ conn: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        default: statusText = "Error"
        }
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/html; charset=utf-8\r\n\r\n\(body)
        """
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }
}
