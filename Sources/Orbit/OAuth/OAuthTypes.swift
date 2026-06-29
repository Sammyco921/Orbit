import Foundation

// MARK: - OAuth Token

struct OAuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: TimeInterval?
    let scope: String?
    let grantedAt: Date
    var isExpired: Bool {
        guard let expiresIn else { return false }
        return Date().timeIntervalSince(grantedAt) > expiresIn
    }
}

// MARK: - OAuth Provider Configuration

struct OAuthProviderConfig: Codable, Sendable {
    let id: String
    let name: String
    let authorizeURL: String
    let tokenURL: String
    let revokeURL: String?
    let scopes: [String]
    let clientId: String
    let clientSecret: String?
    let redirectScheme: String
    let extraParams: [String: String]?

    init(id: String, name: String, authorizeURL: String, tokenURL: String, revokeURL: String? = nil, scopes: [String], clientId: String, clientSecret: String? = nil, redirectScheme: String = "http", extraParams: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
        self.scopes = scopes
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectScheme = redirectScheme
        self.extraParams = extraParams
    }
}

// MARK: - PKCE State

struct OAuthPKCEState: Codable, Sendable {
    let codeVerifier: String
    let codeChallenge: String
    let state: String
    let createdAt: Date
}

// MARK: - Credential

struct OAuthCredential: Codable, Sendable {
    let id: String
    let providerId: String
    let accountName: String?
    let workspaceId: String?
    let token: OAuthToken
    let scopes: [String]
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Errors

enum OAuthError: Error, LocalizedError {
    case invalidState
    case authorizationDenied(String?)
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case noRefreshToken
    case providerNotFound(String)
    case redirectServerFailed(String)
    case storeFailed(String)
    case revocationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidState: return "OAuth state mismatch — possible CSRF attack"
        case .authorizationDenied(let reason): return "Authorization denied\(reason.map { ": \($0)" } ?? "")"
        case .tokenExchangeFailed(let msg): return "Token exchange failed: \(msg)"
        case .refreshFailed(let msg): return "Token refresh failed: \(msg)"
        case .noRefreshToken: return "No refresh token available"
        case .providerNotFound(let id): return "OAuth provider not found: \(id)"
        case .redirectServerFailed(let msg): return "OAuth redirect server error: \(msg)"
        case .storeFailed(let msg): return "Credential store error: \(msg)"
        case .revocationFailed(let msg): return "Token revocation failed: \(msg)"
        }
    }
}
