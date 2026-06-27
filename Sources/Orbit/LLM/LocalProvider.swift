import Foundation

// Phase: Unified local provider — auto-detects Ollama or OpenAI-compatible API.

enum LocalAPIType: String, Sendable {
    case ollama
    case llamaCPP
    case openAICompatible
}

final class LocalProvider: LLMProvider {
    let name = "Local"
    private let baseURL: String
    private let model: String
    private let session: URLSession
    private let apiType: LocalAPIType

    init(baseURL: String = "http://localhost:11434", model: String = "llama3", apiType: LocalAPIType = .ollama) {
        self.baseURL = baseURL
        self.model = model
        self.apiType = apiType
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Detect API type from a running server

    static func detectAPIType(baseURL: String) async -> LocalAPIType {
        let session = URLSession(configuration: .default)
        // Try Ollama first
        if let url = URL(string: "\(baseURL)/api/tags") {
            if let (_, resp) = try? await session.data(from: url),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                return .ollama
            }
        }
        // Fall back to OpenAI-compatible
        return .openAICompatible
    }

    // MARK: - Complete

    func complete(messages: [LLMMessage], parameters: ModelParameters) async throws -> String {
        switch apiType {
        case .ollama:
            return try await completeOllama(messages: messages, parameters: parameters, stream: false)
        case .llamaCPP:
            return try await completeOpenAI(messages: messages, parameters: parameters, stream: false)
        case .openAICompatible:
            return try await completeOpenAI(messages: messages, parameters: parameters, stream: false)
        }
    }

    func completeStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    switch self.apiType {
                    case .ollama:
                        let result = try await self.completeOllamaStreaming(messages: messages, parameters: parameters)
                        for try await chunk in result {
                            continuation.yield(chunk)
                        }
                    case .llamaCPP:
                        let result = try await self.completeOpenAIStreaming(messages: messages, parameters: parameters)
                        for try await chunk in result {
                            continuation.yield(chunk)
                        }
                    case .openAICompatible:
                        let result = try await self.completeOpenAIStreaming(messages: messages, parameters: parameters)
                        for try await chunk in result {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Ollama API

    private func ollamaEndpoint() -> URL? {
        URL(string: "\(baseURL)/api/chat")
    }

    private func completeOllama(messages: [LLMMessage], parameters: ModelParameters, stream: Bool) async throws -> String {
        guard let url = ollamaEndpoint() else {
            throw LLMError.apiError("Invalid Ollama URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var options: [String: Any] = [:]
        if let v = parameters.temperature { options["temperature"] = v }
        if let v = parameters.maxTokens { options["num_predict"] = v }
        if let v = parameters.topP { options["top_p"] = v }

        var body: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map { $0.localPayload() }
        ]
        if !options.isEmpty { body["options"] = options }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError("Ollama returned error: \(text)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let message = json?["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        if let responseText = json?["response"] as? String {
            return responseText
        }
        throw LLMError.invalidResponse
    }

    private func completeOllamaStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = self.ollamaEndpoint() else { throw LLMError.apiError("Invalid Ollama URL") }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var options: [String: Any] = [:]
                    if let v = parameters.temperature { options["temperature"] = v }
                    if let v = parameters.maxTokens { options["num_predict"] = v }
                    if let v = parameters.topP { options["top_p"] = v }

                    var body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { $0.localPayload() }
                    ]
                    if !options.isEmpty { body["options"] = options }
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await session.bytes(for: request)
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            continuation.yield(content)
                        } else if let response = json["response"] as? String {
                            continuation.yield(response)
                        }
                        if json["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - OpenAI-Compatible API

    private func openAIEndpoint() -> URL? {
        URL(string: "\(baseURL)/v1/chat/completions")
    }

    private func completeOpenAI(messages: [LLMMessage], parameters: ModelParameters, stream: Bool) async throws -> String {
        guard let url = openAIEndpoint() else {
            throw LLMError.apiError("Invalid endpoint URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "model": model,
            "stream": stream,
            "messages": messages.map { $0.openAIPayload() }
        ]
        if let t = parameters.temperature { payload["temperature"] = t }
        if let m = parameters.maxTokens { payload["max_tokens"] = m }
        if let p = parameters.topP { payload["top_p"] = p }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown"
            throw LLMError.apiError("API returned \(String(describing: (response as? HTTPURLResponse)?.statusCode)): \(text)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let choices = json?["choices"] as? [[String: Any]],
           let first = choices.first,
           let message = first["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        throw LLMError.invalidResponse
    }

    private func completeOpenAIStreaming(messages: [LLMMessage], parameters: ModelParameters) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = self.openAIEndpoint() else { throw LLMError.apiError("Invalid endpoint URL") }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var payload: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": messages.map { $0.openAIPayload() }
                    ]
                    if let t = parameters.temperature { payload["temperature"] = t }
                    if let m = parameters.maxTokens { payload["max_tokens"] = m }
                    if let p = parameters.topP { payload["top_p"] = p }
                    request.httpBody = try JSONSerialization.data(withJSONObject: payload)

                    let (bytes, _) = try await session.bytes(for: request)
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "), line != "data: [DONE]" else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
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
