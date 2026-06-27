import Foundation

protocol EmbeddingService {
    func embed(text: String) async throws -> [Float]
}

final class OpenAIEmbeddings: EmbeddingService {
    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "text-embedding-3-small") {
        self.apiKey = apiKey
        self.model = model
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    func embed(text: String) async throws -> [Float] {
        guard !apiKey.isEmpty else { throw OrbitError.invalidInput("No API key configured") }
        guard let url = URL(string: "https://api.openai.com/v1/embeddings") else {
            throw OrbitError.embeddingFailed("Invalid response from API")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["model": model, "input": text]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OrbitError.embeddingFailed("Invalid response from API")
        }
        guard httpResponse.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown"
            throw OrbitError.embeddingFailed("OpenAI embeddings returned \(httpResponse.statusCode): \(text)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = json["data"] as? [[String: Any]],
              let first = dataArr.first,
              let embedding = first["embedding"] as? [Double]
        else {
            throw OrbitError.embeddingFailed("Invalid response from API")
        }

        return embedding.map { Float($0) }
    }
}
