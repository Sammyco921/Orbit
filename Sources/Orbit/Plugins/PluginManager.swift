import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "plugin-manager")

final class PluginManager {
    private(set) var plugins: [Plugin] = []
    private(set) var availableUpdates: [PluginUpdateInfo] = []
    private let toolService: ToolService
    private let pluginsDirectory: URL
    private let decoder = JSONDecoder()
    let registryService = PluginRegistryService()
    var isDevelopmentMode = false

    init(toolService: ToolService) {
        self.toolService = toolService
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pluginsDirectory = appSupport.appendingPathComponent("com.orbit").appendingPathComponent("Plugins")
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
    }

    func discover() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: pluginsDirectory, includingPropertiesForKeys: nil) else { return }

        for dir in contents where dir.hasDirectoryPath {
            let manifestURL = dir.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(PluginManifest.self, from: data) else {
                continue
            }
            let enabled = UserDefaults.standard.object(forKey: "plugin_enabled_\(manifest.id)") as? Bool ?? true
            if !plugins.contains(where: { $0.id == manifest.id }) {
                let plugin = Plugin(manifest: manifest, directory: dir, isEnabled: enabled)
                plugins.append(plugin)
                if enabled {
                    loadPlugin(plugin)
                }
            }
        }
    }

    func loadPlugin(_ plugin: Plugin) {
        guard plugin.isEnabled else { return }
        do {
            try plugin.start()
            let toolDefs = try fetchTools(from: plugin)
            registerPluginTools(plugin, toolDefs: toolDefs)
            log.notice("Loaded plugin: \(plugin.id)")
        } catch {
            log.error("Failed to load plugin \(plugin.id): \(error.localizedDescription)")
        }
    }

    func unloadPlugin(_ plugin: Plugin) {
        unregisterPluginTools(plugin)
        plugin.stop()
        log.notice("Unloaded plugin: \(plugin.id)")
    }

    func installPlugin(from url: URL) throws {
        let fm = FileManager.default
        let data = try Data(contentsOf: url)
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        let pluginDir = pluginsDirectory.appendingPathComponent(manifest.id)
        try fm.createDirectory(at: pluginDir, withIntermediateDirectories: true)

        let destURL = pluginDir.appendingPathComponent("plugin.json")
        try data.write(to: destURL)
    }

    func installPlugin(fromDirectory src: URL) throws {
        let fm = FileManager.default
        let manifestURL = src.appendingPathComponent("plugin.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(PluginManifest.self, from: data)
        let pluginDir = pluginsDirectory.appendingPathComponent(manifest.id)

        if fm.fileExists(atPath: pluginDir.path) {
            try fm.removeItem(at: pluginDir)
        }
        try fm.copyItem(at: src, to: pluginDir)
    }

    func uninstallPlugin(_ plugin: Plugin) {
        unloadPlugin(plugin)
        try? FileManager.default.removeItem(at: plugin.directory)
        plugins.removeAll { $0.id == plugin.id }
        clearPermissionsApproval(for: plugin.id)
    }

    func reloadAll() {
        for plugin in plugins where plugin.isEnabled {
            unloadPlugin(plugin)
        }
        discover()
    }

    // MARK: - Registry Installation

    /// Install a plugin from the registry by ID, with permission approval and verification
    func installFromRegistry(id: String, approvedPermissions: [PluginPermission]? = nil) async throws {
        let index = try await registryService.fetchIndex()
        guard let regPlugin = index.plugins.first(where: { $0.id == id }) else {
            throw PluginRegistryError.pluginNotFound(id)
        }

        // Check Orbit version compatibility
        guard registryService.officialRegistry.isCompatible(requiredOrbitVersion: regPlugin.requiredOrbitVersion) else {
            throw PluginRegistryError.versionMismatch(
                required: regPlugin.requiredOrbitVersion ?? "?",
                current: OfficialPluginRegistry.currentOrbitVersion
            )
        }

        // Check permission approval
        let permissions = approvedPermissions ?? regPlugin.permissions
        guard hasApprovedPermissions(for: id) || approvedPermissions != nil else {
            throw PluginRegistryError.permissionDenied("Permissions must be approved before installation")
        }

        // Download
        let data = try await registryService.officialRegistry.downloadPlugin(regPlugin)

        // Verify checksum
        guard registryService.officialRegistry.verifyChecksum(data: data, expected: regPlugin.checksum) else {
            throw PluginRegistryError.checksumMismatch
        }

        // Extract to plugins directory
        try extractPlugin(data: data, regPlugin: regPlugin, permissions: Array(Set(permissions)))

        // Mark permissions as approved
        markPermissionsApproved(for: id)

        discover()
    }

    /// Apply an update for a specific plugin
    func applyUpdate(_ update: PluginUpdateInfo) async throws {
        if let existing = plugins.first(where: { $0.id == update.pluginId }) {
            unloadPlugin(existing)
        }
        try await installFromRegistry(id: update.pluginId, approvedPermissions: update.permissions)
        availableUpdates.removeAll { $0.pluginId == update.pluginId }
    }

    // MARK: - Update Checking

    /// Check for available updates for all installed plugins
    func checkForUpdates() async {
        let installed = plugins.map { ($0.id, $0.manifest.version) }
        guard !installed.isEmpty else { return }
        do {
            let index = try await registryService.fetchIndex()
            var updates: [PluginUpdateInfo] = []
            for installed in installed {
                guard let regPlugin = index.plugins.first(where: { $0.id == installed.0 }) else { continue }
                guard regPlugin.version.compare(installed.1, options: .numeric) == .orderedDescending else { continue }
                guard registryService.officialRegistry.isCompatible(requiredOrbitVersion: regPlugin.requiredOrbitVersion) else { continue }
                updates.append(PluginUpdateInfo(
                    pluginId: installed.0,
                    currentVersion: installed.1,
                    availableVersion: regPlugin.version,
                    downloadURL: regPlugin.downloadURL,
                    permissions: regPlugin.permissions,
                    checksum: regPlugin.checksum,
                    requiredOrbitVersion: regPlugin.requiredOrbitVersion
                ))
            }
            await MainActor.run {
                availableUpdates = updates
            }
        } catch {
            log.error("Failed to check for plugin updates: \(error.localizedDescription)")
        }
    }

    func enablePlugin(_ plugin: Plugin) {
        plugin.isEnabled = true
        loadPlugin(plugin)
    }

    func disablePlugin(_ plugin: Plugin) {
        plugin.isEnabled = false
        unloadPlugin(plugin)
    }

    // MARK: - Private

    private func extractPlugin(data: Data, regPlugin: RegistryPlugin, permissions: [PluginPermission]) throws {
        let fm = FileManager.default
        let pluginDir = pluginsDirectory.appendingPathComponent(regPlugin.id)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orbit-plugin-\(regPlugin.id)-\(UUID().uuidString.prefix(8))")

        defer { try? fm.removeItem(at: tmpDir) }

        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        if regPlugin.downloadURL.hasSuffix(".zip") {
            try extractZip(data: data, to: tmpDir)
        } else {
            try extractFlat(data: data, to: tmpDir, regPlugin: regPlugin)
        }

        // Write updated manifest with permissions
        writePermissionsToManifest(pluginDir: tmpDir, permissions: permissions)

        // Atomically move into place
        if fm.fileExists(atPath: pluginDir.path) {
            try fm.removeItem(at: pluginDir)
        }
        try fm.moveItem(at: tmpDir, to: pluginDir)
    }

    private func writePermissionsToManifest(pluginDir: URL, permissions: [PluginPermission]) {
        let manifestURL = pluginDir.appendingPathComponent("plugin.json")
        guard var manifest = try? decoder.decode(PluginManifest.self, from: Data(contentsOf: manifestURL)) else { return }
        let updated = PluginManifest(
            id: manifest.id,
            name: manifest.name,
            version: manifest.version,
            description: manifest.description,
            author: manifest.author,
            icon: manifest.icon,
            entryPoint: manifest.entryPoint,
            tools: manifest.tools,
            permissions: permissions
        )
        if let encoded = try? JSONEncoder().encode(updated) {
            try? encoded.write(to: manifestURL)
        }
    }

    private func extractZip(data: Data, to directory: URL) throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try data.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", tmpURL.path, "-d", directory.path]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw PluginRegistryError.extractFailed("unzip exited with code \(process.terminationStatus)")
        }
    }

    private func extractFlat(data: Data, to directory: URL, regPlugin: RegistryPlugin) throws {
        struct FlatBundle: Codable {
            let files: [String: String]
        }
        let bundle = try decoder.decode(FlatBundle.self, from: data)
        for (filename, content) in bundle.files {
            let fileURL = directory.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
    }

    private func fetchTools(from plugin: Plugin) throws -> [(PluginToolDef, ToolDefinition)] {
        plugin.manifest.tools.map { toolDef in
            let schema = ToolSchema(parameters: toolDef.parameters?.map { param in
                ToolParameter(
                    name: param.name,
                    description: param.description,
                    type: ParameterType(string: param.type) ?? .string,
                    required: param.required
                )
            } ?? [])
            let definition = ToolDefinition(
                id: "plugin_\(plugin.id)_\(toolDef.name)",
                name: toolDef.name,
                description: toolDef.description,
                inputSchema: schema,
                requiredPermission: .requiresApproval
            )
            return (toolDef, definition)
        }
    }

    private func registerPluginTools(_ plugin: Plugin, toolDefs: [(PluginToolDef, ToolDefinition)]) {
        for (toolDef, definition) in toolDefs {
            let wrapper = PluginTool(plugin: plugin, toolName: toolDef.name, definition: definition)
            toolService.toolRegistry.register(wrapper)
        }
    }

    private func unregisterPluginTools(_ plugin: Plugin) {
        for toolDef in plugin.manifest.tools {
            let id = "plugin_\(plugin.id)_\(toolDef.name)"
            toolService.toolRegistry.unregister(id: id)
        }
    }
}

private final class PluginTool: Tool {
    let definition: ToolDefinition
    private weak var plugin: Plugin?
    private let toolName: String

    init(plugin: Plugin, toolName: String, definition: ToolDefinition) {
        self.plugin = plugin
        self.toolName = toolName
        self.definition = definition
    }

    func run(input: [String: String]) async throws -> String {
        guard let plugin else { return "[Plugin unavailable]" }
        return try await plugin.callTool(name: toolName, arguments: input)
    }
}

extension ParameterType {
    init?(string: String) {
        switch string.lowercased() {
        case "string": self = .string
        case "integer", "int": self = .integer
        case "number": self = .number
        case "boolean", "bool": self = .boolean
        default: return nil
        }
    }
}
