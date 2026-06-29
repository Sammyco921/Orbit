import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "llm")

final class LLMService {
    private var provider: LLMProvider?
    private let settingsProvider: () -> AppSettings

    init(settingsProvider: @escaping () -> AppSettings) {
        self.settingsProvider = settingsProvider
    }

    func resetProvider() {
        provider = nil
    }

    func currentProvider(config: ModelConfig? = nil) -> LLMProvider {
        if let provider { return provider }
        let p = createProvider(config: config)
        provider = p
        return p
    }

    func createProvider(config: ModelConfig? = nil) -> LLMProvider {
        let s = settingsProvider()
        let type = config?.providerType ?? s.providerType
        let primary: LLMProvider
        switch type {
        case .openAI:
            primary = OpenAIProvider(apiKey: s.openAIKey, model: config?.model ?? "gpt-4o")
        case .anthropic:
            primary = AnthropicProvider(apiKey: s.anthropicKey, model: config?.model ?? "claude-sonnet-4-20250514")
        case .local:
            let url = s.localModelURL
            let apiType = LocalAPIType(rawValue: s.localAPIType) ?? .ollama
            primary = LocalProvider(baseURL: url, model: config?.model ?? s.localModelName, apiType: apiType)
        }

        // Build fallback chain: primary → secondary configured provider (if any)
        var fallbacks = [primary]
        if type != .openAI, !s.openAIKey.isEmpty {
            fallbacks.append(CachedLLMProvider(wrapping: OpenAIProvider(apiKey: s.openAIKey), ttl: 300))
        }
        if type != .anthropic, !s.anthropicKey.isEmpty {
            fallbacks.append(CachedLLMProvider(wrapping: AnthropicProvider(apiKey: s.anthropicKey), ttl: 300))
        }
        if type != .local, !s.localModelURL.isEmpty {
            fallbacks.append(CachedLLMProvider(wrapping: LocalProvider(baseURL: s.localModelURL), ttl: 300))
        }

        if fallbacks.count == 1 {
            return CachedLLMProvider(wrapping: fallbacks[0], ttl: 300)
        }
        let chain = FallbackLLMProvider(providers: fallbacks)
        return CachedLLMProvider(wrapping: chain, ttl: 300)
    }

    func activeConfig(for conversation: Conversation?) -> ModelConfig? {
        conversation?.modelConfig
    }

    func activeParameters(for conversation: Conversation?) -> ModelParameters {
        conversation?.modelConfig?.parameters ?? ModelParameters()
    }
}
