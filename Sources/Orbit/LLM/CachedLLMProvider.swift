import Foundation
import CryptoKit

final class CachedLLMProvider: LLMProvider {
    private let wrapped: LLMProvider
    private let cache = NSCache<NSString, CacheEntry>()
    private let ttl: TimeInterval

    init(wrapping provider: LLMProvider, ttl: TimeInterval = 300) {
        self.wrapped = provider
        self.ttl = ttl
        cache.countLimit = 100
    }

    var name: String { wrapped.name }

    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        let key = cacheKey(messages: messages, parameters: parameters)
        if let entry = cache.object(forKey: key as NSString), Date().timeIntervalSince(entry.timestamp) < ttl {
            return entry.response
        }
        let response = try await wrapped.complete(messages: messages, parameters: parameters)
        cache.setObject(CacheEntry(response: response), forKey: key as NSString)
        return response
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        wrapped.completeStreaming(messages: messages, parameters: parameters)
    }

    private func cacheKey(messages: [LLMMessage], parameters: ModelParameters) -> String {
        let data = (try? JSONEncoder().encode(CacheableRequest(messages: messages, parameters: parameters))) ?? Data()
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        return "\(wrapped.name)-\(hash)"
    }
}

private struct CacheableRequest: Encodable {
    let messages: [LLMMessage]
    let parameters: ModelParameters
}

final class CacheEntry: NSObject {
    let response: String
    let timestamp: Date
    init(response: String) {
        self.response = response
        self.timestamp = Date()
    }
}
