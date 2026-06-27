import Foundation

final class Plan: Identifiable, Codable {
    let id: UUID
    let summary: String
    var steps: [Step]
    var status: Status

    enum Status: String, Codable {
        case pending
        case approved
        case rejected
        case executing
        case completed
        case failed
    }

    init(summary: String, steps: [Step]) {
        self.id = UUID()
        self.summary = summary
        self.steps = steps
        self.status = .pending
    }
}
