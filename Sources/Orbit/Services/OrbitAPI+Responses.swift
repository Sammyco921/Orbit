import Foundation
import Network

// MARK: - Response Helpers

extension OrbitAPI {
    func sendJSON(status: Int, body: String, connection: NWConnection) {
        let response = "HTTP/1.1 \(status) \(statusText(status))\(crlf)" +
            "Content-Type: application/json\(crlf)" +
            "Content-Length: \(body.utf8.count)\(crlf)" +
            "Connection: close\(crlf)" +
            "Access-Control-Allow-Origin: null\(crlf)" +
            "\(crlf)" +
            body
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    func sendSSEHeaders(_ connection: NWConnection) {
        let headers = "HTTP/1.1 200 OK\(crlf)" +
            "Content-Type: text/event-stream\(crlf)" +
            "Cache-Control: no-cache\(crlf)" +
            "Connection: keep-alive\(crlf)" +
            "Access-Control-Allow-Origin: null\(crlf)" +
            "\(crlf)"
        connection.send(content: headers.data(using: .utf8), completion: .idempotent)
    }

    func sendSSEEvent(type: String, data: String, connection: NWConnection) {
        let escaped = data.replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let event = "event: \(type)\(crlf)data: \(escaped)\(crlf)\(crlf)"
        connection.send(content: event.data(using: .utf8), completion: .idempotent)
    }

    private func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return ""
        }
    }
}
