import Foundation

struct ClassifiedEntity: Sendable {
    let type: DiscoveryEntityType
    let name: String
    let confidence: Double
    let extractedMetadata: [String: String]
}

final class ClassificationService {
    private let llmProvider: LLMProvider

    init(llmProvider: LLMProvider) { self.llmProvider = llmProvider }

    func classify(emailSubject: String, emailBody: String) async -> ClassifiedEntity? {
        let trimmed = String(emailBody.prefix(2000))
        let prompt = """
        Analyze this email and classify it as exactly one of: account_creation, subscription, invoice, or unrelated.
        If it's a subscription or invoice, extract: name, amount, currency, billing_cycle, next_billing_date (ISO).
        If it's an account_creation, extract: service_name, account_email.
        Return valid JSON with keys: type, name, confidence, metadata (object of extracted fields).
        Only return the JSON. No explanation.

        Subject: \(emailSubject)
        Body: \(trimmed)
        """

        guard let response = try? await llmProvider.complete(messages: [
            LLMMessage(role: .user, content: prompt)
        ]) else { return nil }
        return parseJSON(response)
    }

    func classify(title: String, content: String) async -> (type: DiscoveryEntityType, summary: String)? {
        let trimmed = String(content.prefix(2000))
        let prompt = """
        Categorize this document as: document, invoice, project, or unrelated.
        If invoice, extract vendor, amount, date.
        Return JSON with keys: type, summary.
        Only return the JSON.

        Title: \(title)
        Content: \(trimmed)
        """

        guard let response = try? await llmProvider.complete(messages: [
            LLMMessage(role: .user, content: prompt)
        ]) else { return nil }
        if let data = cleanedJSON(response).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let rawType = json["type"] {
            let type = DiscoveryEntityType(rawValue: rawType) ?? .document
            return (type, json["summary"] ?? title)
        }
        return nil
    }

    private func cleanedJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseJSON(_ text: String) -> ClassifiedEntity? {
        let cleaned = cleanedJSON(text)
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawType = json["type"] as? String,
              let entityType = entityType(for: rawType),
              let name = json["name"] as? String else { return nil }

        let confidence = (json["confidence"] as? Double) ?? 0.5
        let metadata = (json["metadata"] as? [String: String]) ?? [:]
        return ClassifiedEntity(type: entityType, name: name, confidence: confidence, extractedMetadata: metadata)
    }

    private func entityType(for raw: String) -> DiscoveryEntityType? {
        switch raw {
        case "account_creation": return .account
        case "subscription": return .subscription
        case "invoice": return .invoice
        case "document": return .document
        case "project": return .project
        default: return nil
        }
    }
}
