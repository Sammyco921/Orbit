import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "llm-fallback")

final class FallbackLLMProvider: LLMProvider {
    let name: String
    private let providers: [LLMProvider]

    init(providers: [LLMProvider]) {
        self.providers = providers
        self.name = providers.map { $0.name }.joined(separator: " | ")
    }

    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        var lastError: Error?
        for provider in providers {
            do {
                return try await provider.complete(messages: messages, parameters: parameters)
            } catch {
                lastError = error
                log.warning("Provider \(provider.name) failed: \(error.localizedDescription). Trying next...")
            }
        }
        throw lastError ?? LLMError.apiError("All providers failed")
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var lastError: Error?
                for provider in providers {
                    do {
                        for try await chunk in provider.completeStreaming(messages: messages, parameters: parameters) {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                        return
                    } catch {
                        lastError = error
                        log.warning("Provider \(provider.name) streaming failed: \(error.localizedDescription). Trying next...")
                    }
                }
                continuation.finish(throwing: lastError ?? LLMError.apiError("All providers failed"))
            }
        }
    }
}
