import Foundation

struct OllamaModel: Decodable, Identifiable, Equatable {
    var id: String { name }
    let name: String
    let modifiedAt: String?
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
    }
}

struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]?
}

final class OllamaService {
    private let baseURL: String
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    private var tagsURL: URL? { URL(string: "\(baseURL)/api/tags") }
    private var pullURL: URL? { URL(string: "\(baseURL)/api/pull") }
    private var chatURL: URL? { URL(string: "\(baseURL)/api/chat") }

    func checkRunning() async -> Bool {
        guard let url = tagsURL else { return false }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func fetchModels() async throws -> [OllamaModel] {
        guard let url = tagsURL else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models ?? []
    }

    func pullModel(name: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let url = pullURL else {
                    continuation.finish(throwing: URLError(.badURL))
                    return
                }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body: [String: Any] = ["name": name, "stream": true]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    for try await line in bytes.lines {
                        guard !line.isEmpty,
                              let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let status = json["status"] as? String {
                            continuation.yield(status)
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

    func warmModel(name: String) async throws -> Bool {
        guard let url = chatURL else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": name,
            "messages": [["role": "user", "content": "hello"]],
            "keep_alive": "10m",
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }

    static func launchOllama() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/ollama")
        task.arguments = ["serve"]
        try? task.run()
    }
}
