import Foundation
import CryptoKit

// MARK: - Models

/// A plugin listed in the registry
struct RegistryPlugin: Codable, Identifiable {
    let id: String
    let name: String
    let version: String
    let description: String
    let author: String?
    let icon: String?
    let categories: [String]?
    let homepage: String?
    let entryPoint: String
    let downloadURL: String
    let tools: [RegistryToolDef]
    let permissions: [PluginPermission]
    let checksum: String
    let requiredOrbitVersion: String?
}

struct RegistryToolDef: Codable {
    let name: String
    let description: String
    let parameters: [RegistryParameterDef]?
}

struct RegistryParameterDef: Codable {
    let name: String
    let description: String
    let type: String
    let required: Bool
}

/// The full registry index
struct PluginRegistryIndex: Codable {
    let version: Int
    let registry: RegistryMetadata
    let plugins: [RegistryPlugin]
}

struct RegistryMetadata: Codable {
    let name: String
    let url: String
    let description: String
}

/// Information about an available update
struct PluginUpdateInfo {
    let pluginId: String
    let currentVersion: String
    let availableVersion: String
    let downloadURL: String
    let permissions: [PluginPermission]
    let checksum: String
    let requiredOrbitVersion: String?
}

// MARK: - Registry Protocol

protocol PluginRegistry: AnyObject {
    var name: String { get }
    var metadata: RegistryMetadata? { get }
    func fetchIndex(forceRefresh: Bool) async throws -> PluginRegistryIndex
    func downloadPlugin(_ plugin: RegistryPlugin) async throws -> Data
    func verifyChecksum(data: Data, expected: String) -> Bool
    func isCompatible(requiredOrbitVersion: String?) -> Bool
}

// MARK: - Errors

enum PluginRegistryError: LocalizedError {
    case offline(underlying: Error)
    case invalidRegistry(String)
    case downloadFailed(String)
    case checksumMismatch
    case versionMismatch(required: String, current: String)
    case pluginNotFound(String)
    case permissionDenied(String)
    case extractFailed(String)

    var errorDescription: String? {
        switch self {
        case .offline(let error):
            return "Could not connect to registry: \(error.localizedDescription)"
        case .invalidRegistry(let detail):
            return "Invalid registry response: \(detail)"
        case .downloadFailed(let detail):
            return "Download failed: \(detail)"
        case .checksumMismatch:
            return "Download integrity check failed. The file may be corrupted."
        case .versionMismatch(let required, let current):
            return "This plugin requires Orbit \(required) or later. You have \(current)."
        case .pluginNotFound(let id):
            return "Plugin '\(id)' not found in registry."
        case .permissionDenied(let permission):
            return "Required permission not granted: \(permission)"
        case .extractFailed(let detail):
            return "Could not extract plugin: \(detail)"
        }
    }
}

// MARK: - Orbit Official Registry

final class OfficialPluginRegistry: PluginRegistry {
    let name = "Orbit Official"
    private(set) var metadata: RegistryMetadata?
    private let session: URLSession = .shared
    private let decoder = JSONDecoder()
    private var cachedIndex: PluginRegistryIndex?
    private var lastFetchDate: Date?

    static let defaultURL = "https://raw.githubusercontent.com/Orbit-LLM/orbit-plugins/main/index.json"
    static let currentOrbitVersion = "1.0.0"

    func fetchIndex(forceRefresh: Bool = false) async throws -> PluginRegistryIndex {
        if !forceRefresh, let cached = cachedIndex, let last = lastFetchDate, Date().timeIntervalSince(last) < 3600 {
            return cached
        }
        guard let url = URL(string: Self.defaultURL) else {
            throw PluginRegistryError.invalidRegistry("Invalid URL")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw PluginRegistryError.invalidRegistry("No HTTP response")
            }
            guard http.statusCode == 200 else {
                throw PluginRegistryError.invalidRegistry("HTTP \(http.statusCode)")
            }
            let index = try decoder.decode(PluginRegistryIndex.self, from: data)
            metadata = index.registry
            cachedIndex = index
            lastFetchDate = Date()
            return index
        } catch let error as PluginRegistryError {
            throw error
        } catch let error as URLError {
            throw PluginRegistryError.offline(underlying: error)
        } catch let error as DecodingError {
            throw PluginRegistryError.invalidRegistry(error.localizedDescription)
        } catch {
            throw PluginRegistryError.offline(underlying: error)
        }
    }

    func downloadPlugin(_ plugin: RegistryPlugin) async throws -> Data {
        guard let url = URL(string: plugin.downloadURL) else {
            throw PluginRegistryError.downloadFailed("Invalid download URL")
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw PluginRegistryError.downloadFailed("No HTTP response")
            }
            guard http.statusCode == 200 else {
                throw PluginRegistryError.downloadFailed("HTTP \(http.statusCode)")
            }
            return data
        } catch let error as URLError {
            throw PluginRegistryError.offline(underlying: error)
        } catch {
            throw PluginRegistryError.downloadFailed(error.localizedDescription)
        }
    }

    func verifyChecksum(data: Data, expected: String) -> Bool {
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return hash == expected.lowercased()
    }

    func isCompatible(requiredOrbitVersion: String?) -> Bool {
        guard let required = requiredOrbitVersion, !required.isEmpty else { return true }
        return required.compare(Self.currentOrbitVersion, options: .numeric) != .orderedDescending
    }
}

// MARK: - Registry Service

final class PluginRegistryService {
    let officialRegistry = OfficialPluginRegistry()

    var allRegistries: [PluginRegistry] {
        [officialRegistry]
    }

    func fetchIndex(forceRefresh: Bool = false) async throws -> PluginRegistryIndex {
        try await officialRegistry.fetchIndex(forceRefresh: forceRefresh)
    }
}

// MARK: - Permission Approval

struct PermissionApproval {
    let pluginId: String
    let pluginName: String
    let pluginVersion: String
    let permissions: [PluginPermission]
    let isApproved: Bool
    let approvedAt: Date
}

func hasApprovedPermissions(for pluginId: String) -> Bool {
    UserDefaults.standard.bool(forKey: "plugin_permissions_approved_\(pluginId)")
}

func markPermissionsApproved(for pluginId: String) {
    UserDefaults.standard.set(true, forKey: "plugin_permissions_approved_\(pluginId)")
}

func clearPermissionsApproval(for pluginId: String) {
    UserDefaults.standard.removeObject(forKey: "plugin_permissions_approved_\(pluginId)")
}
