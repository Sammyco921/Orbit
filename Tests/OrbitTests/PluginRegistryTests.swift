import Testing
import Foundation
@testable import Orbit

struct PluginRegistryTests {

    @Test func registryPluginCodable() throws {
        let plugin = RegistryPlugin(
            id: "test-plugin",
            name: "Test Plugin",
            version: "1.0.0",
            description: "A test plugin",
            author: "Test Author",
            icon: "icon.png",
            categories: ["utility"],
            homepage: "https://example.com",
            entryPoint: "main.py",
            downloadURL: "https://example.com/plugin.zip",
            tools: [RegistryToolDef(name: "hello", description: "Says hello", parameters: nil)],
            permissions: [.browser, .filesystem],
            checksum: "abc123def456",
            requiredOrbitVersion: "1.0.0"
        )
        let data = try JSONEncoder().encode(plugin)
        let decoded = try JSONDecoder().decode(RegistryPlugin.self, from: data)
        #expect(decoded.id == "test-plugin")
        #expect(decoded.name == "Test Plugin")
        #expect(decoded.version == "1.0.0")
        #expect(decoded.tools.count == 1)
        #expect(decoded.tools.first?.name == "hello")
        #expect(decoded.permissions.count == 2)
        #expect(decoded.checksum == "abc123def456")
        #expect(decoded.requiredOrbitVersion == "1.0.0")
    }

    @Test func registryIndexCodable() throws {
        let metadata = RegistryMetadata(
            name: "Orbit Official",
            url: "https://example.com",
            description: "Test registry"
        )
        let index = PluginRegistryIndex(version: 1, registry: metadata, plugins: [
            RegistryPlugin(
                id: "p1", name: "Plugin 1", version: "1.0",
                description: "First", author: nil, icon: nil,
                categories: nil, homepage: nil, entryPoint: "run.py",
                downloadURL: "https://example.com/p1.zip", tools: [],
                permissions: [],
                checksum: "def456abc789",
                requiredOrbitVersion: nil
            )
        ])
        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(PluginRegistryIndex.self, from: data)
        #expect(decoded.version == 1)
        #expect(decoded.plugins.count == 1)
        #expect(decoded.plugins[0].id == "p1")
    }

    @Test func versionComparison() {
        let newer = "2.0.0"
        let older = "1.5.0"
        #expect(newer.compare(older, options: .numeric) == .orderedDescending)
        #expect(older.compare(newer, options: .numeric) == .orderedAscending)
        #expect("1.0.0".compare("1.0.0", options: .numeric) == .orderedSame)
    }
}
