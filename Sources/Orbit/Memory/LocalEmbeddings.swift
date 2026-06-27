import Foundation
import NaturalLanguage

final class LocalEmbeddings: EmbeddingService {
    private let embedding: NLEmbedding

    init?(language: NLLanguage = .english) {
        guard let model = NLEmbedding.wordEmbedding(for: language) else { return nil }
        self.embedding = model
    }

    func embed(text: String) async throws -> [Float] {
        let dim = embedding.dimension
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [Float](repeating: 0, count: dim) }

        var sum = [Double](repeating: 0, count: dim)
        var count = 0
        for word in words {
            if let vec = embedding.vector(for: word) {
                for i in 0..<min(vec.count, dim) {
                    sum[i] += vec[i]
                }
                count += 1
            }
        }
        guard count > 0 else { return [Float](repeating: 0, count: dim) }
        return sum.map { Float($0) / Float(count) }
    }
}
