import Foundation

enum ProviderType: String, Codable, CaseIterable {
    case openAI
    case anthropic
    case local

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .local: "Local"
        }
    }
}

enum LLMError: Error {
    case invalidResponse
    case apiError(String)
    case notConfigured
    case networkError(Error)
}

protocol LLMProvider {
    var name: String { get }
    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String
    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error>
}

extension LLMProvider {
    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, parameters: ModelParameters())
    }
    func completeStreaming(messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        completeStreaming(messages: messages, parameters: ModelParameters())
    }
}
