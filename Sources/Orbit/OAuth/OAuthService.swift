import Foundation
import CryptoKit
import OSLog
import AppKit

private let log = Logger(subsystem: "com.orbit", category: "oauth")

final class OAuthService {
    private let tokenStore: TokenStore
    private let providerRegistry: OAuthProviderRegistry
    private let redirectServer: OAuthRedirectServer

    init(tokenStore: TokenStore, providerRegistry: OAuthProviderRegistry) {
        self.tokenStore = tokenStore
        self.providerRegistry = providerRegistry
        self.redirectServer = OAuthRedirectServer()
    }

    // MARK: - Authorization URL

    func authorizationURL(providerId: String, workspaceId: String?, context: ExecutionContext) async throws -> (url: URL, stateId: String) {
        guard let provider = providerRegistry.provider(id: providerId) else {
            throw OAuthError.providerNotFound(providerId)
        }

        let pkce = generatePKCE()
        let stateId = pkce.state

        let port = try await redirectServer.start(port: 0)
        let         redirectURI = "http://127.0.0.1:\(port)/callback"

        var components = URLComponents(string: provider.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: provider.clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: provider.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: stateId),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
        ]

        if let extra = provider.extraParams {
            for (key, value) in extra {
                components.queryItems?.append(URLQueryItem(name: key, value: value))
            }
        }

        guard let url = components.url else {
            throw OAuthError.redirectServerFailed("Failed to construct authorization URL")
        }

        storePKCE(pkce, for: stateId)
        setStateProvider(stateId: stateId, providerId: providerId)

        return (url, stateId)
    }

    // MARK: - Handle Redirect

    func handleRedirect(callbackURL: String, expectedState: String) async throws -> OAuthCredential {
        guard let components = URLComponents(string: callbackURL) else {
            throw OAuthError.authorizationDenied("Invalid callback URL")
        }

        if let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
            throw OAuthError.authorizationDenied(error)
        }

        guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.authorizationDenied("No authorization code in response")
        }

        let state = components.queryItems?.first(where: { $0.name == "state" })?.value ?? ""
        guard state == expectedState else {
            throw OAuthError.invalidState
        }

        guard let pkce = retrievePKCE(for: state) else {
            throw OAuthError.invalidState
        }

        let provider = try resolveProvider(from: callbackURL)

        let baseRedirect = callbackURL.components(separatedBy: "?").first ?? callbackURL
        let token = try await exchangeCode(
            code: code,
            codeVerifier: pkce.codeVerifier,
            redirectURI: baseRedirect,
            provider: provider
        )

        let credential = OAuthCredential(
            id: UUID().uuidString,
            providerId: provider.id,
            accountName: nil,
            workspaceId: nil,
            token: token,
            scopes: provider.scopes,
            createdAt: Date(),
            updatedAt: Date()
        )

        try tokenStore.saveToken(credential)
        clearPKCE(for: state)

        return credential
    }

    // MARK: - Full Auth Flow

    func authenticate(providerId: String, workspaceId: String?, context: ExecutionContext) async throws -> OAuthCredential {
        if let existing = tokenStore.credential(providerId: providerId, workspaceId: workspaceId) {
            if !existing.token.isExpired {
                return existing
            }
            if let refreshed = try await refresh(credential: existing, context: context) {
                return refreshed
            }
            try tokenStore.deleteCredentials(providerId: providerId, workspaceId: workspaceId)
        }

        let (authURL, stateId) = try await authorizationURL(providerId: providerId, workspaceId: workspaceId, context: context)

        // Open the URL in the user's default browser
        NSWorkspace.shared.open(authURL)

        let callbackURL: String
        do {
            callbackURL = try await redirectServer.waitForCallback()
        } catch {
            await redirectServer.cancel()
            throw error
        }
        await redirectServer.cancel()

        return try await handleRedirect(callbackURL: callbackURL, expectedState: stateId)
    }

    // MARK: - Refresh Lock

    private var refreshInProgress: Set<String> = []
    private let refreshLock = NSLock()

    // MARK: - Token Refresh

    func refresh(credential: OAuthCredential, context: ExecutionContext) async throws -> OAuthCredential? {
        refreshLock.lock()
        if refreshInProgress.contains(credential.id) {
            refreshLock.unlock()
            if let stored = tokenStore.credential(id: credential.id) {
                return stored
            }
            throw OAuthError.refreshFailed("Concurrent refresh detected")
        }
        refreshInProgress.insert(credential.id)
        refreshLock.unlock()

        defer {
            refreshLock.lock()
            refreshInProgress.remove(credential.id)
            refreshLock.unlock()
        }

        guard let refreshToken = credential.token.refreshToken else {
            throw OAuthError.noRefreshToken
        }

        guard let provider = providerRegistry.provider(id: credential.providerId) else {
            throw OAuthError.providerNotFound(credential.providerId)
        }

        var request = URLRequest(url: URL(string: provider.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": provider.clientId
        ]
        if let secret = provider.clientSecret {
            bodyParams["client_secret"] = secret
        }

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.refreshFailed("HTTP \(String(describing: (response as? HTTPURLResponse)?.statusCode ?? 0)): <response body redacted>")
        }

        let token = try parseTokenResponse(data: data, existingRefreshToken: refreshToken)

        let updated = OAuthCredential(
            id: credential.id,
            providerId: credential.providerId,
            accountName: credential.accountName,
            workspaceId: credential.workspaceId,
            token: token,
            scopes: credential.scopes,
            createdAt: credential.createdAt,
            updatedAt: Date()
        )

        try tokenStore.saveToken(updated)
        return updated
    }

    // MARK: - Revoke

    func revoke(credentialId: String, context: ExecutionContext) async throws {
        guard let credential = tokenStore.retrieveFromKeychain(id: credentialId) else {
            try tokenStore.deleteCredential(id: credentialId)
            return
        }

        if let provider = providerRegistry.provider(id: credential.providerId),
           let revokeURL = provider.revokeURL {
            var request = URLRequest(url: URL(string: revokeURL)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "token=\(credential.token.accessToken)"
            request.httpBody = body.data(using: .utf8)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                throw OAuthError.revocationFailed("HTTP \(httpResponse.statusCode)")
            }
        }

        try tokenStore.deleteCredential(id: credentialId)
    }

    // MARK: - PKCE Storage

    private var pkceStore: [String: OAuthPKCEState] = [:]
    private var stateProviderMap: [String: String] = [:]
    private let pkceLock = NSLock()

    private func storePKCE(_ pkce: OAuthPKCEState, for state: String) {
        pkceLock.lock()
        pkceStore[state] = pkce
        pkceLock.unlock()
    }

    private func retrievePKCE(for state: String) -> OAuthPKCEState? {
        pkceLock.lock()
        defer { pkceLock.unlock() }
        return pkceStore[state]
    }

    private func clearPKCE(for state: String) {
        pkceLock.lock()
        pkceStore.removeValue(forKey: state)
        stateProviderMap.removeValue(forKey: state)
        pkceLock.unlock()
    }

    private func setStateProvider(stateId: String, providerId: String) {
        pkceLock.lock()
        stateProviderMap[stateId] = providerId
        pkceLock.unlock()
    }

    private func providerIdForState(_ state: String) -> String? {
        pkceLock.lock()
        defer { pkceLock.unlock() }
        return stateProviderMap[state]
    }

    // MARK: - PKCE Generation

    private func generatePKCE() -> OAuthPKCEState {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(verifier: verifier)
        let state = UUID().uuidString
        return OAuthPKCEState(codeVerifier: verifier, codeChallenge: challenge, state: state, createdAt: Date())
    }

    private func generateCodeVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncodedString()
    }

    private func generateCodeChallenge(verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }

    // MARK: - Token Exchange

    private func exchangeCode(code: String, codeVerifier: String, redirectURI: String, provider: OAuthProviderConfig) async throws -> OAuthToken {
        var request = URLRequest(url: URL(string: provider.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        if provider.id == "github" {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        var bodyParams: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": provider.clientId,
            "code_verifier": codeVerifier
        ]
        if let secret = provider.clientSecret {
            bodyParams["client_secret"] = secret
        }

        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.tokenExchangeFailed("No HTTP response")
        }

        if httpResponse.statusCode != 200 {
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): <response body redacted>")
        }

        return try parseTokenResponse(data: data, existingRefreshToken: nil)
    }

    private func parseTokenResponse(data: Data, existingRefreshToken: String?) throws -> OAuthToken {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OAuthError.tokenExchangeFailed("Invalid JSON response")
        }

        guard let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("No access_token in response: <response body redacted>")
        }

        return OAuthToken(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? existingRefreshToken,
            tokenType: json["token_type"] as? String ?? "Bearer",
            expiresIn: json["expires_in"] as? TimeInterval,
            scope: json["scope"] as? String,
            grantedAt: Date()
        )
    }

    private func resolveProvider(from callbackURL: String) throws -> OAuthProviderConfig {
        guard let components = URLComponents(string: callbackURL),
              let state = components.queryItems?.first(where: { $0.name == "state" })?.value,
              let providerId = providerIdForState(state),
              let provider = providerRegistry.provider(id: providerId) else {
            throw OAuthError.providerNotFound("unknown")
        }
        return provider
    }
}

// MARK: - Base64 URL Encoding

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
