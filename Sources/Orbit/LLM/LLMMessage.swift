import Foundation

struct LLMMessage: Codable {
    let role: Role
    let content: String
    let images: [ImageAttachment]

    enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String, images: [ImageAttachment] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

extension LLMMessage {
    func openAIPayload() -> [String: Any] {
        if images.isEmpty {
            return ["role": role.rawValue, "content": content]
        }
        var parts: [[String: Any]] = [["type": "text", "text": content]]
        for img in images {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:\(img.mimeType);base64,\(img.base64Data)", "detail": "auto"]
            ])
        }
        return ["role": role.rawValue, "content": parts]
    }

    func anthropicPayload() -> [String: Any] {
        if images.isEmpty {
            return ["role": role.rawValue, "content": content]
        }
        var parts: [[String: Any]] = [["type": "text", "text": content]]
        for img in images {
            parts.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": img.mimeType,
                    "data": img.base64Data
                ]
            ])
        }
        return ["role": role.rawValue, "content": parts]
    }

    func localPayload() -> [String: Any] {
        var dict: [String: Any] = ["role": role.rawValue, "content": content]
        if !images.isEmpty {
            dict["images"] = images.map { $0.base64Data }
        }
        return dict
    }
}
