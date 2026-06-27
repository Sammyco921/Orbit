import Foundation

struct ModelParameters: Codable, Equatable {
    var temperature: Double?
    var maxTokens: Int?
    var topP: Double?
}
