import Foundation

struct ImageAttachment: Codable, Equatable {
    let mimeType: String
    let base64Data: String
}
