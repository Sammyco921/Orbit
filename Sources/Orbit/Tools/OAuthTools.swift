import Foundation

// MARK: - Connect Service Tool

final class ConnectServiceTool: Tool {
    var definition = ToolDefinition(
        id: "connectService",
        name: "Connect Service",
        description: "Connect Orbit to an external service (Google, GitHub, Slack, Notion, Microsoft, Atlassian) via OAuth. Opens a browser window for you to authorize.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "provider", description: "The service to connect to (google, github, slack, notion, microsoft, atlassian)", type: .string, required: true)
        ])
    )

    let oauthService: OAuthService

    init(oauthService: OAuthService) {
        self.oauthService = oauthService
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let providerId = input["provider"]?.lowercased(), !providerId.isEmpty else {
            return "No provider specified. Available: google, github, slack, notion, microsoft, atlassian"
        }

        let credential = try await oauthService.authenticate(providerId: providerId, workspaceId: nil, context: ctx)
        return "✅ Connected to \(credential.providerId). Token expires in \(credential.token.expiresIn.map { "\(Int($0))s" } ?? "unknown")."
    }
}

// MARK: - List Connections Tool

final class ListConnectionsTool: Tool {
    var definition = ToolDefinition(
        id: "listConnections",
        name: "List Connections",
        description: "List all OAuth-connected services and their status.",
        inputSchema: ToolSchema(parameters: [])
    )

    let tokenStore: TokenStore

    init(tokenStore: TokenStore) {
        self.tokenStore = tokenStore
    }

    func run(input: [String: String]) async throws -> String {
        let credentials = tokenStore.allCredentials(workspaceId: nil)
        if credentials.isEmpty {
            return "No services are connected yet. Use connectService to add one."
        }

        var lines = ["Connected services:"]
        for cred in credentials {
            let status = cred.token.isExpired ? "⚠️ Token expired" : "✅ Active"
            let expires = cred.token.expiresIn.map { " (expires in \(Int($0))s)" } ?? ""
            lines.append("- \(cred.providerId)\(cred.accountName.map { " (\($0))" } ?? ""): \(status)\(expires)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Disconnect Service Tool

final class DisconnectServiceTool: Tool {
    var definition = ToolDefinition(
        id: "disconnectService",
        name: "Disconnect Service",
        description: "Disconnect Orbit from a connected service and revoke the access token.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "provider", description: "The service to disconnect (google, github, slack, notion, microsoft, atlassian)", type: .string, required: true)
        ])
    )

    let oauthService: OAuthService
    let tokenStore: TokenStore

    init(oauthService: OAuthService, tokenStore: TokenStore) {
        self.oauthService = oauthService
        self.tokenStore = tokenStore
    }

    func run(input: [String: String]) async throws -> String {
        guard let ctx = ExecutionContext.current else {
            return "No execution context available."
        }
        guard let providerId = input["provider"]?.lowercased(), !providerId.isEmpty else {
            return "No provider specified."
        }

        guard let credential = tokenStore.credential(providerId: providerId, workspaceId: nil) else {
            return "No connection found for '\(providerId)'."
        }

        try await oauthService.revoke(credentialId: credential.id, context: ctx)
        return "✅ Disconnected from \(providerId). Token revoked."
    }
}
