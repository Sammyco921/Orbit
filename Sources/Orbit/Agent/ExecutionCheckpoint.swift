import Foundation
import GRDB

struct ExecutionCheckpoint: Codable, Sendable {
    let id: String
    let goalDescription: String
    let messages: [LLMMessage]
    let stepCount: Int
    let toolFailures: [String: Int]
    let conversationId: String?
    let createdAt: Date

    // Multi-agent coordination state (optional, populated by PlannerAgent)
    var agentStates: [String: AgentCheckpointState]?
    var completedSubGoals: [String]?
    var subGoalRetryCounts: [String: Int]?
    var plan: [SubGoalRecord]?
    var sharedMemoryData: Data?
}

struct AgentCheckpointState: Codable, Sendable {
    let agentId: String
    let agentType: String
    let status: String
    let currentGoal: String?
    let lastOutput: String?
    let error: String?
    let taskCount: Int
}

struct SubGoalRecord: Codable, Sendable {
    let description: String
    let assignedAgentType: String
    let status: String
    let retryCount: Int
    let error: String?
}

final class CheckpointManager {
    private let db: DatabaseQueue

    init(db: DatabaseQueue) {
        self.db = db
    }

    func save(_ checkpoint: ExecutionCheckpoint) throws {
        let messagesData = try JSONEncoder().encode(checkpoint.messages)
        let messagesJSON = String(data: messagesData, encoding: .utf8)!
        let failuresData = try JSONEncoder().encode(checkpoint.toolFailures)
        let failuresJSON = String(data: failuresData, encoding: .utf8)!
        let agentStatesData = checkpoint.agentStates.flatMap { try? JSONEncoder().encode($0) }
        let agentStatesJSON = agentStatesData.map { String(data: $0, encoding: .utf8) }
        let completedData = checkpoint.completedSubGoals.flatMap { try? JSONEncoder().encode($0) }
        let completedJSON = completedData.map { String(data: $0, encoding: .utf8) }
        let retryData = checkpoint.subGoalRetryCounts.flatMap { try? JSONEncoder().encode($0) }
        let retryJSON = retryData.map { String(data: $0, encoding: .utf8) }
        let planData = checkpoint.plan.flatMap { try? JSONEncoder().encode($0) }
        let planJSON = planData.map { String(data: $0, encoding: .utf8) }

        try db.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO checkpoints (id, goalDescription, messagesJSON, stepCount, toolFailuresJSON, conversationId, createdAt, agentStatesJSON, completedSubGoalsJSON, subGoalRetryCountsJSON, planJSON, sharedMemoryData)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                checkpoint.id,
                checkpoint.goalDescription,
                messagesJSON,
                checkpoint.stepCount,
                failuresJSON,
                checkpoint.conversationId,
                checkpoint.createdAt.timeIntervalSince1970,
                agentStatesJSON,
                completedJSON,
                retryJSON,
                planJSON,
                checkpoint.sharedMemoryData
            ])
        }
    }

    func loadLatest() -> ExecutionCheckpoint? {
        try? db.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT * FROM checkpoints ORDER BY createdAt DESC LIMIT 1")
            guard let row else { return nil }
            return buildCheckpoint(from: row)
        }
    }

    func load(id: String) -> ExecutionCheckpoint? {
        try? db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM checkpoints WHERE id = ?", arguments: [id]) else { return nil }
            return buildCheckpoint(from: row)
        }
    }

    func delete(id: String) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM checkpoints WHERE id = ?", arguments: [id])
        }
    }

    func deleteAll() throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM checkpoints")
        }
    }

    var checkpointCount: Int {
        (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM checkpoints") }) ?? 0
    }

    private func buildCheckpoint(from row: Row) -> ExecutionCheckpoint? {
        guard let id = row["id"] as? String,
              let goalDescription = row["goalDescription"] as? String,
              let messagesJSON = row["messagesJSON"] as? String,
              let messagesData = messagesJSON.data(using: .utf8),
              let messages = try? JSONDecoder().decode([LLMMessage].self, from: messagesData)
        else {
            return nil
        }

        let stepCount = (row["stepCount"] as? Int) ?? (row["stepCount"] as? Int64).map { Int($0) } ?? 0
        let createdAtInterval = (row["createdAt"] as? TimeInterval) ?? (row["createdAt"] as? Double) ?? 0
        let failuresJSON = (row["toolFailuresJSON"] as? String) ?? "{}"
        let toolFailures = (try? JSONDecoder().decode([String: Int].self, from: Data(failuresJSON.utf8))) ?? [:]
        let conversationId = row["conversationId"] as? String

        let agentStates: [String: AgentCheckpointState]? = (row["agentStatesJSON"] as? String).flatMap { data in
            (try? JSONDecoder().decode([String: AgentCheckpointState].self, from: Data(data.utf8)))
        }
        let completedSubGoals: [String]? = (row["completedSubGoalsJSON"] as? String).flatMap { data in
            (try? JSONDecoder().decode([String].self, from: Data(data.utf8)))
        }
        let subGoalRetryCounts: [String: Int]? = (row["subGoalRetryCountsJSON"] as? String).flatMap { data in
            (try? JSONDecoder().decode([String: Int].self, from: Data(data.utf8)))
        }
        let plan: [SubGoalRecord]? = (row["planJSON"] as? String).flatMap { data in
            (try? JSONDecoder().decode([SubGoalRecord].self, from: Data(data.utf8)))
        }

        let sharedMemoryData = row["sharedMemoryData"] as? Data

        return ExecutionCheckpoint(
            id: id,
            goalDescription: goalDescription,
            messages: messages,
            stepCount: stepCount,
            toolFailures: toolFailures,
            conversationId: conversationId,
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            agentStates: agentStates,
            completedSubGoals: completedSubGoals,
            subGoalRetryCounts: subGoalRetryCounts,
            plan: plan,
            sharedMemoryData: sharedMemoryData
        )
    }
}
