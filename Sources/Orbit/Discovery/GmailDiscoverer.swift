import Foundation

final class GmailDiscoverer: Discoverer {
    let serviceName = "gmail"
    private let connector: GmailConnector

    init(connector: GmailConnector) { self.connector = connector }

    func scan(store: DiscoveryStore, classification: ClassificationService) async throws -> ScanResult {
        var accounts: [DiscoveredAccount] = []
        var subscriptions: [DiscoveredSubscription] = []
        var invoices: [DiscoveredInvoice] = []

        // Search for account creation emails
        let accountMessages = try await search(query: "subject:\"welcome\" OR subject:\"verify your email\" OR subject:\"confirm your account\" OR subject:\"account created\"")
        for msg in accountMessages {
            guard let id = msg["id"] as? String,
                  let snippet = msg["snippet"] as? String else { continue }
            let fullBody = try? await getMessageBody(id: id)
            guard let entity = await classification.classify(emailSubject: snippet, emailBody: fullBody ?? snippet),
                  entity.type == .account else { continue }
            let email = entity.extractedMetadata["account_email"] ?? ""
            let name = entity.extractedMetadata["service_name"] ?? entity.name
            accounts.append(DiscoveredAccount(id: "gmail_acct_\(id)", service: "gmail", accountName: name, accountEmail: email, accountURL: nil, sourceMessageId: id, discoveredAt: Date()))
        }

        // Search for subscription emails
        let subMessages = try await search(query: "subject:\"receipt\" OR subject:\"invoice\" OR subject:\"subscription\" OR subject:\"your bill\" OR subject:\"thank you for your order\"")
        for msg in subMessages {
            guard let id = msg["id"] as? String,
                  let snippet = msg["snippet"] as? String else { continue }
            let fullBody = try? await getMessageBody(id: id)
            guard let entity = await classification.classify(emailSubject: snippet, emailBody: fullBody ?? snippet),
                  entity.type == .subscription || entity.type == .invoice else { continue }
            let name = entity.extractedMetadata["name"] ?? entity.name
            let amount = Double(entity.extractedMetadata["amount"] ?? "")
            let currency = entity.extractedMetadata["currency"] ?? "USD"
            let billingCycle = entity.extractedMetadata["billing_cycle"]
            let nextBilling = entity.extractedMetadata["next_billing_date"]

            if entity.type == .subscription {
                subscriptions.append(DiscoveredSubscription(id: "gmail_sub_\(id)", service: "gmail", name: name, amount: amount, currency: currency, billingCycle: billingCycle, nextBillingDate: nextBilling, sourceMessageId: id, discoveredAt: Date(), isActive: true))
            } else {
                invoices.append(DiscoveredInvoice(id: "gmail_inv_\(id)", service: "gmail", vendor: name, amount: amount ?? 0, currency: currency, invoiceDate: nextBilling ?? "", dueDate: nil, isRecurring: billingCycle != nil, sourceMessageId: id, sourceFileId: nil, discoveredAt: Date()))
            }
        }

        // Persist
        for acct in accounts { try? store.saveAccount(acct) }
        for sub in subscriptions { try? store.saveSubscription(sub) }
        for inv in invoices { try? store.saveInvoice(inv) }

        return ScanResult(accounts: accounts, subscriptions: subscriptions, documents: [], invoices: invoices)
    }

    func incrementalScan(store: DiscoveryStore, classification: ClassificationService, since: Date) async throws -> ScanResult {
        // For incremental, use after: filter
        let dateStr = ISO8601Formatter.string(from: since)
        var accounts: [DiscoveredAccount] = []
        var subscriptions: [DiscoveredSubscription] = []
        var invoices: [DiscoveredInvoice] = []

        let messages = try await search(query: "after:\(dateStr)")
        for msg in messages {
            guard let id = msg["id"] as? String,
                  let snippet = msg["snippet"] as? String else { continue }
            let fullBody = try? await getMessageBody(id: id)
            guard let entity = await classification.classify(emailSubject: snippet, emailBody: fullBody ?? snippet) else { continue }
            switch entity.type {
            case .account:
                accounts.append(DiscoveredAccount(id: "gmail_acct_\(id)", service: "gmail", accountName: entity.name, accountEmail: entity.extractedMetadata["account_email"], accountURL: nil, sourceMessageId: id, discoveredAt: Date()))
            case .subscription:
                subscriptions.append(DiscoveredSubscription(id: "gmail_sub_\(id)", service: "gmail", name: entity.name, amount: Double(entity.extractedMetadata["amount"] ?? ""), currency: entity.extractedMetadata["currency"] ?? "USD", billingCycle: entity.extractedMetadata["billing_cycle"], nextBillingDate: entity.extractedMetadata["next_billing_date"], sourceMessageId: id, discoveredAt: Date(), isActive: true))
            case .invoice:
                invoices.append(DiscoveredInvoice(id: "gmail_inv_\(id)", service: "gmail", vendor: entity.name, amount: Double(entity.extractedMetadata["amount"] ?? "") ?? 0, currency: entity.extractedMetadata["currency"] ?? "USD", invoiceDate: entity.extractedMetadata["next_billing_date"] ?? "", dueDate: nil, isRecurring: false, sourceMessageId: id, sourceFileId: nil, discoveredAt: Date()))
            default: break
            }
        }

        for acct in accounts { try? store.saveAccount(acct) }
        for sub in subscriptions { try? store.saveSubscription(sub) }
        for inv in invoices { try? store.saveInvoice(inv) }

        return ScanResult(accounts: accounts, subscriptions: subscriptions, documents: [], invoices: invoices)
    }

    // MARK: - Helpers

    private func search(query: String) async throws -> [[String: Any]] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let (data, _) = try await connector.authenticatedRequest(
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages?q=\(encoded)&maxResults=50"
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else { return [] }
        return messages
    }

    private func getMessageBody(id: String) async throws -> String? {
        let (data, _) = try await connector.authenticatedRequest(
            url: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full"
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else { return nil }
        return extractBody(from: payload)
    }

    private func extractBody(from payload: [String: Any]) -> String {
        if let parts = payload["parts"] as? [[String: Any]] {
            for part in parts {
                if (part["mimeType"] as? String) == "text/plain",
                   let body = part["body"] as? [String: Any],
                   let data = body["data"] as? String,
                   let decoded = Data(base64Encoded: data
                    .replacingOccurrences(of: "-", with: "+")
                    .replacingOccurrences(of: "_", with: "/")) {
                    return String(data: decoded, encoding: .utf8) ?? ""
                }
                if let subParts = part["parts"] as? [[String: Any]] {
                    let sub = extractBody(from: ["parts": subParts])
                    if !sub.isEmpty { return sub }
                }
            }
        }
        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String,
           let decoded = Data(base64Encoded: data.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
           let text = String(data: decoded, encoding: .utf8) { return text }
        return ""
    }
}

private let ISO8601Formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy/MM/dd"
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f
}()
