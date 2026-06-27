import Foundation
import Network
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "webhook")

struct WebhookRegistration: Codable {
    let id: String
    let providerId: String
    let eventType: String
    let targetURL: String?
    let workflowId: String?
    let secret: String?
    let createdAt: Date

    var channelID: String { "\(providerId)_\(eventType)_\(id.prefix(8))" }
}

actor WebhookService {
    private var registrations: [String: WebhookRegistration] = [:]
    private var listener: NWListener?
    private var workflowHandler: ((String, [String: Any]) async -> Void)?

    init(workflowHandler: (@escaping (String, [String: Any]) async -> Void) = { _, _ in }) {
        self.workflowHandler = workflowHandler
    }

    func setWorkflowHandler(_ handler: @escaping (String, [String: Any]) async -> Void) {
        self.workflowHandler = handler
    }

    // MARK: - Registration

    func register(_ webhook: WebhookRegistration) {
        registrations[webhook.id] = webhook
    }

    func unregister(id: String) {
        registrations.removeValue(forKey: id)
    }

    func registration(id: String) -> WebhookRegistration? {
        registrations[id]
    }

    func allRegistrations() -> [WebhookRegistration] {
        Array(registrations.values)
    }

    // MARK: - Incoming Webhook Server

    func startServer(port: UInt16) async throws -> Int {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        let resolvedPort = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int, Error>) in
            listener.serviceRegistrationUpdateHandler = { change in
                if case .add(let endpoint) = change {
                    if case .hostPort(_, let actualPort) = endpoint {
                        cont.resume(returning: Int(actualPort.rawValue))
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { return }
                conn.stateUpdateHandler = { state in
                    if state == .ready {
                        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                            if let error {
                                log.error("Webhook receive error: \(error.localizedDescription)")
                                conn.cancel()
                                return
                            }
                            if let data, let request = String(data: data, encoding: .utf8) {
                                Task { await self.handleWebhookRequest(request, connection: conn) }
                            }
                            conn.cancel()
                        }
                    }
                }
                conn.start(queue: .global())
            }

            listener.start(queue: .global())
        }

        log.notice("Webhook server started on port \(resolvedPort)")
        return resolvedPort
    }

    func stopServer() {
        listener?.cancel()
        listener = nil
    }

    private func handleWebhookRequest(_ request: String, connection: NWConnection) async {
        guard let (path, body) = Self.parseHTTPRequest(request) else {
            Self.sendWebhookResponse(connection, statusCode: 400, body: "Bad Request")
            return
        }

        // Notify the workflow handler
        let event: [String: Any] = [
            "path": path,
            "body": body ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        await workflowHandler?("webhook", event)

        Self.sendWebhookResponse(connection, statusCode: 200, body: "OK")
    }

    private static nonisolated func parseHTTPRequest(_ request: String) -> (path: String, body: String?)? {
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else { return nil }
        let path = components[1]

        // Find body after empty line
        let parts = request.components(separatedBy: "\r\n\r\n")
        let body = parts.count > 1 ? parts[1] : nil

        return (path, body)
    }

    private static nonisolated func sendWebhookResponse(_ conn: NWConnection, statusCode: Int, body: String) {
        let statusText = statusCode == 200 ? "OK" : "Error"
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: text/plain\r\n\r\n\(body)"
        conn.send(content: response.data(using: .utf8), completion: .contentProcessed({ _ in }))
    }

}
