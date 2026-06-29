import Foundation
import UniformTypeIdentifiers

// MARK: - File Handling

extension Orchestrator {
    func handleDroppedFile(_ url: URL) async {
        if activeConversationId == nil { newConversation() }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]

        if imageExtensions.contains(url.pathExtension.lowercased()) {
            guard let data = try? Data(contentsOf: url) else {
                addMessage(Message(role: .system, content: "Failed to read dropped image: \(url.lastPathComponent)"))
                return
            }
            let mimeType: String
            switch url.pathExtension.lowercased() {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "gif": mimeType = "image/gif"
            case "webp": mimeType = "image/webp"
            case "bmp": mimeType = "image/bmp"
            case "tiff", "heif": mimeType = "image/tiff"
            case "heic": mimeType = "image/heic"
            default: mimeType = "image/png"
            }
            let base64 = data.base64EncodedString()
            let attachment = ImageAttachment(mimeType: mimeType, base64Data: base64)
            addMessage(Message(role: .user, content: "📷 Image: \(url.lastPathComponent)", images: [attachment]))
        } else {
            do {
                let data = try Data(contentsOf: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    addMessage(Message(role: .system, content: "Dropped file: \(url.lastPathComponent) — binary or unsupported format"))
                    return
                }
                let ext = url.pathExtension
                let fileType = ext.isEmpty ? "" : ext.uppercased()
                addMessage(Message(role: .user, content: "📄 \(fileType) File: \(url.lastPathComponent) (\(content.count) chars)\n\nFrom: `\(url.path)`\n\n```\(ext)\n\(content)\n```"))
            } catch {
                addMessage(Message(role: .system, content: "Failed to read dropped file: \(url.lastPathComponent) — \(error.localizedDescription)"))
            }
        }
    }

    func handleScreenshot(_ attachment: ImageAttachment, label: String) async {
        if activeConversationId == nil { newConversation() }
        addMessage(Message(role: .user, content: "📷 Screenshot: \(label)", images: [attachment]))
        await sendMessage("Analyze this screenshot. Describe what you see in detail.")
    }
}
