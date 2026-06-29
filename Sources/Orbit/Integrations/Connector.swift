import Foundation

// MARK: - Connector Protocol

protocol Connector: AnyObject {
    var id: String { get }
    var name: String { get }
    var requiredScopes: [String] { get }
    var tools: [Tool] { get }
}

// MARK: - Base API Connector

class APIConnector {
    let oauthService: OAuthService
    let tokenStore: TokenStore
    let providerId: String

    init(oauthService: OAuthService, tokenStore: TokenStore, providerId: String) {
        self.oauthService = oauthService
        self.tokenStore = tokenStore
        self.providerId = providerId
    }

    func authenticatedRequest(
        method: String = "GET",
        url: String,
        body: Data? = nil,
        headers: [String: String] = [:],
        workspaceId: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard var credential = tokenStore.credential(providerId: providerId, workspaceId: workspaceId) else {
            throw IntegrationError.notConnected(providerId)
        }

        if credential.token.isExpired {
            let ctx = ExecutionContext.current ?? ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: workspaceId, source: .internal, timeout: 30, createdAt: Date())
            guard let refreshed = try await oauthService.refresh(credential: credential, context: ctx) else {
                throw IntegrationError.tokenRefreshFailed(providerId)
            }
            credential = refreshed
        }

        guard let requestURL = URL(string: url) else {
            throw IntegrationError.requestFailed("Invalid URL: \(url)")
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("Bearer \(credential.token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IntegrationError.requestFailed("No HTTP response")
        }

        if httpResponse.statusCode == 401 {
            let ctx = ExecutionContext.current ?? ExecutionContext(executionId: UUID().uuidString, conversationId: nil, workspaceId: workspaceId, source: .internal, timeout: 30, createdAt: Date())
            if let refreshed = try await oauthService.refresh(credential: credential, context: ctx) {
                request.setValue("Bearer \(refreshed.token.accessToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw IntegrationError.requestFailed("No HTTP response on retry")
                }
                return (retryData, retryHTTP)
            }
            throw IntegrationError.tokenRefreshFailed(providerId)
        }

        if httpResponse.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw IntegrationError.requestFailed("HTTP \(httpResponse.statusCode): \(body.prefix(500))")
        }

        return (data, httpResponse)
    }

    func jsonBody(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}

// MARK: - Errors

enum IntegrationError: Error, LocalizedError {
    case notConnected(String)
    case tokenRefreshFailed(String)
    case requestFailed(String)
    case invalidResponse(String)
    case rateLimited(String)
    case webhookError(String)

    var errorDescription: String? {
        switch self {
        case .notConnected(let provider): return "Not connected to \(provider). Use connectService first."
        case .tokenRefreshFailed(let provider): return "Token refresh failed for \(provider). Reconnect using connectService."
        case .requestFailed(let msg): return "API request failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .rateLimited(let msg): return "Rate limited: \(msg)"
        case .webhookError(let msg): return "Webhook error: \(msg)"
        }
    }
}
