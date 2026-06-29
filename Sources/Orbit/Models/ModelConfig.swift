import Foundation

struct ModelConfig: Codable, Equatable {
    var providerType: ProviderType
    var model: String
    var parameters: ModelParameters?

    static let defaults: [ProviderType: String] = [
        .openAI: "gpt-4o",
        .anthropic: "claude-sonnet-4-20250514",
        .local: "llama3"
    ]

    static func localDefault(from settings: AppSettings) -> String {
        settings.localModelName.isEmpty ? "llama3" : settings.localModelName
    }

    static func `default`(for type: ProviderType) -> ModelConfig {
        ModelConfig(providerType: type, model: defaults[type] ?? "gpt-4o")
    }
}
