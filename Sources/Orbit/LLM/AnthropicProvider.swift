import Foundation

final class AnthropicProvider: LLMProvider {
    let name = "Anthropic"
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private static let apiVersion = "2023-06-01"

    init(apiKey: String, model: String = "claude-sonnet-4-20250514") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        guard let url = URL(string: baseURL) else { throw LLMError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": parameters.maxTokens ?? 4096,
            "messages": messages.map { $0.anthropicPayload() }
        ]
        if let v = parameters.temperature { body["temperature"] = v }
        if let v = parameters.topP { body["top_p"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError("Anthropic returned \(httpResponse.statusCode): \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String
        else {
            throw LLMError.invalidResponse
        }

        return text
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: baseURL) else { throw LLMError.invalidResponse }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

                    var body: [String: Any] = [
                        "model": model,
                        "max_tokens": parameters.maxTokens ?? 4096,
                        "stream": true,
                        "messages": messages.map { $0.anthropicPayload() }
                    ]
                    if let v = parameters.temperature { body["temperature"] = v }
                    if let v = parameters.topP { body["top_p"] = v }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await session.bytes(for: request)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = line.dropFirst(6)

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        if json["type"] as? String == "content_block_delta",
                           let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String {
                            continuation.yield(text)
                        } else if json["type"] as? String == "message_stop" {
                            break
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
