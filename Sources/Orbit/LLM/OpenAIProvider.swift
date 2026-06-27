import Foundation

final class OpenAIProvider: LLMProvider {
    let name = "OpenAI"
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String, model: String = "gpt-4o") {
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { $0.openAIPayload() }
        ]
        if let v = parameters.temperature { body["temperature"] = v }
        if let v = parameters.maxTokens { body["max_tokens"] = v }
        if let v = parameters.topP { body["top_p"] = v }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError("OpenAI returned \(httpResponse.statusCode): \(errorText)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse
        }

        return content
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
        guard let url = URL(string: baseURL) else { throw LLMError.invalidResponse }
        var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages.map { $0.openAIPayload() },
                        "stream": true
                    ]
                    if let v = parameters.temperature { body["temperature"] = v }
                    if let v = parameters.maxTokens { body["max_tokens"] = v }
                    if let v = parameters.topP { body["top_p"] = v }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        throw LLMError.apiError("Stream request failed")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = line.dropFirst(6)
                        guard !jsonStr.isEmpty else { continue }

                        if jsonStr == "[DONE]" { break }

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String
                        else { continue }

                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
