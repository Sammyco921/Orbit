import Foundation

final class OAuthProviderRegistry {
    private var providers: [String: OAuthProviderConfig] = [:]

    init() {
        registerDefaults()
    }

    func register(_ config: OAuthProviderConfig) {
        providers[config.id] = config
    }

    func provider(id: String) -> OAuthProviderConfig? {
        providers[id]
    }

    func allProviders() -> [OAuthProviderConfig] {
        Array(providers.values)
    }

    private func registerDefaults() {
        // Google — need clientId from user
        register(OAuthProviderConfig(
            id: "google",
            name: "Google",
            authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenURL: "https://oauth2.googleapis.com/token",
            revokeURL: "https://oauth2.googleapis.com/revoke",
            scopes: ["openid", "email", "profile"],
            clientId: "",  // user must configure
            redirectScheme: "http",
            extraParams: ["access_type": "offline", "prompt": "consent"]
        ))

        // GitHub
        register(OAuthProviderConfig(
            id: "github",
            name: "GitHub",
            authorizeURL: "https://github.com/login/oauth/authorize",
            tokenURL: "https://github.com/login/oauth/access_token",
            revokeURL: "https://api.github.com/applications/{client_id}/token",
            scopes: ["repo", "user"],
            clientId: "",
            redirectScheme: "http",
            extraParams: nil
        ))

        // Microsoft
        register(OAuthProviderConfig(
            id: "microsoft",
            name: "Microsoft",
            authorizeURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            revokeURL: nil,
            scopes: ["User.Read", "Mail.Read", "Files.ReadWrite"],
            clientId: "",
            redirectScheme: "http",
            extraParams: nil
        ))

        // Slack
        register(OAuthProviderConfig(
            id: "slack",
            name: "Slack",
            authorizeURL: "https://slack.com/oauth/v2/authorize",
            tokenURL: "https://slack.com/api/oauth.v2.access",
            revokeURL: nil,
            scopes: ["channels:read", "chat:write", "users:read"],
            clientId: "",
            redirectScheme: "http",
            extraParams: nil
        ))

        // Notion
        register(OAuthProviderConfig(
            id: "notion",
            name: "Notion",
            authorizeURL: "https://api.notion.com/v1/oauth/authorize",
            tokenURL: "https://api.notion.com/v1/oauth/token",
            revokeURL: nil,
            scopes: [],
            clientId: "",
            redirectScheme: "http",
            extraParams: nil
        ))

        // Atlassian
        register(OAuthProviderConfig(
            id: "atlassian",
            name: "Atlassian",
            authorizeURL: "https://auth.atlassian.com/authorize",
            tokenURL: "https://auth.atlassian.com/oauth/token",
            revokeURL: nil,
            scopes: ["read:jira-user", "read:jira-work", "offline_access"],
            clientId: "",
            redirectScheme: "http",
            extraParams: ["audience": "api.atlassian.com"]
        ))
    }
}
