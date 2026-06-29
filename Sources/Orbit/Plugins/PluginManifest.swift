import Foundation

struct PluginManifest: Codable {
    let id: String
    let name: String
    let version: String
    let description: String
    let author: String?
    let icon: String?
    let entryPoint: String
    let tools: [PluginToolDef]
    let permissions: [PluginPermission]?
}

struct PluginToolDef: Codable {
    let name: String
    let description: String
    let parameters: [PluginParameterDef]?
}

struct PluginParameterDef: Codable {
    let name: String
    let description: String
    let type: String
    let required: Bool
}
