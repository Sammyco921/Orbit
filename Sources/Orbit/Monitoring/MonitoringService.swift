import Foundation
import GRDB
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "monitor")

// MARK: - Metric Model

struct MetricRecord: Codable, Sendable {
    let id: String
    let bucket: String
    let metricName: String
    let metricValue: Double
    let recordedAt: TimeInterval
}

struct AlertRecord: Codable, Sendable, Identifiable {
    let id: String
    let alertType: String
    let severity: String
    let title: String
    let message: String
    let sourceId: String?
    let sourceType: String?
    let recordedAt: TimeInterval
    var acknowledged: Bool
}

// MARK: - MonitoringService

final class MonitoringService {
    private let db: DatabaseQueue
    private let eventBus: EventBus
    private var cancellables: [() -> Void] = []

    private var activeExecutions: [String: ActiveExecution] = [:]
    private let lock = NSLock()

    struct ActiveExecution {
        let type: String
        let name: String
        let startedAt: Date
        var stepCount: Int
        var errorCount: Int
    }

    init(db: DatabaseQueue, eventBus: EventBus) {
        self.db = db
        self.eventBus = eventBus
    }

    deinit {
        stop()
    }

    func start() {
        subscribeToEvents()
    }

    func stop() {
        for cancel in cancellables { cancel() }
        cancellables.removeAll()
    }

    // MARK: - Event Subscriptions

    private func subscribeToEvents() {
        cancellables.append(eventBus.subscribe(ToolExecutedEvent.self) { [weak self] _ in
            self?.recordMetric(name: "tool.execution", value: 1)
        })

        cancellables.append(eventBus.subscribe(WorkflowStartedEvent.self) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.activeExecutions[event.executionId] = ActiveExecution(
                type: "workflow", name: event.workflowName, startedAt: event.timestamp,
                stepCount: 0, errorCount: 0
            )
            self.lock.unlock()
            self.recordMetric(name: "workflow.started", value: 1)
        })

        cancellables.append(eventBus.subscribe(WorkflowStepCompletedEvent.self) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.activeExecutions[event.executionId]?.stepCount += 1
            if event.outcome == "failed" {
                self.activeExecutions[event.executionId]?.errorCount += 1
            }
            self.lock.unlock()
            self.recordMetric(name: "workflow.step.\(event.outcome)", value: 1)
            self.recordMetric(name: "workflow.step.duration", value: event.durationMs)
        })

        cancellables.append(eventBus.subscribe(WorkflowCompletedEvent.self) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.activeExecutions.removeValue(forKey: event.executionId)
            self.lock.unlock()
            self.recordMetric(name: "workflow.completed.\(event.status)", value: 1)
            self.recordMetric(name: "workflow.duration", value: event.totalDurationMs)

            if event.status == "failed" {
                self.createAlert(
                    type: "workflow_failure", severity: "error",
                    title: "Workflow '\(event.workflowId)' failed",
                    message: event.error ?? "Unknown error after \(Int(event.totalDurationMs))ms",
                    sourceId: event.executionId, sourceType: "workflow_execution"
                )
            }
        })

        cancellables.append(eventBus.subscribe(AgentActionEvent.self) { [weak self] event in
            guard let self else { return }
            self.recordMetric(name: "agent.action.\(event.actionType)", value: 1)

            if event.actionType == "error" {
                self.lock.lock()
                self.activeExecutions[event.executionId]?.errorCount += 1
                let count = self.activeExecutions[event.executionId]?.errorCount ?? 0
                self.lock.unlock()

                if count >= 3 {
                    self.createAlert(
                        type: "agent_repeated_failure", severity: "warning",
                        title: "Agent \(event.executionId.prefix(8))... failed \(count) times",
                        message: event.detail ?? "Repeated agent errors",
                        sourceId: event.executionId, sourceType: "agent_execution"
                    )
                }
            }
        })

        cancellables.append(eventBus.subscribe(GoalStartedEvent.self) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.activeExecutions[event.goalId] = ActiveExecution(
                type: "goal", name: event.description, startedAt: event.timestamp,
                stepCount: 0, errorCount: 0
            )
            self.lock.unlock()
            self.recordMetric(name: "goal.started", value: 1)
        })

        cancellables.append(eventBus.subscribe(GoalCompletedEvent.self) { [weak self] event in
            guard let self else { return }
            self.lock.lock()
            self.activeExecutions.removeValue(forKey: event.goalId)
            self.lock.unlock()
            self.recordMetric(name: "goal.completed.\(event.outcome.hasPrefix("success") ? "success" : "failed")", value: 1)

            if event.outcome.hasPrefix("failed") || event.outcome.hasPrefix("errored") {
                self.createAlert(
                    type: "goal_failure", severity: "error",
                    title: "Goal failed",
                    message: event.outcome,
                    sourceId: event.goalId, sourceType: "goal"
                )
            }
        })

        log.notice("Monitoring subscribed to all execution events")
    }

    // MARK: - Pruning

    private let metricsTTL: TimeInterval = 7 * 86400
    private let alertsTTL: TimeInterval = 30 * 86400

    private func pruneMetrics() {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM monitoring_metrics WHERE recordedAt < ?", arguments: [Date().timeIntervalSince1970 - metricsTTL])
        }
    }

    private func pruneAlerts() {
        try? db.write { db in
            try db.execute(sql: "DELETE FROM monitoring_alerts WHERE recordedAt < ?", arguments: [Date().timeIntervalSince1970 - alertsTTL])
        }
    }

    // MARK: - Metrics Recording

    func recordMetric(name: String, value: Double) {
        let bucket = currentBucket()
        do {
            try db.write { database in
                try database.execute(sql: """
                    INSERT INTO monitoring_metrics (id, bucket, metricName, metricValue, recordedAt)
                    VALUES (?, ?, ?, ?, ?)
                """, arguments: [UUID().uuidString, bucket, name, value, Date().timeIntervalSince1970])
            }
            pruneMetrics()
        } catch {
            log.warning("Failed to record metric '\(name)': \(error.localizedDescription)")
        }
    }

    func createAlert(type: String, severity: String, title: String, message: String, sourceId: String? = nil, sourceType: String? = nil) {
        let alert = AlertRecord(
            id: UUID().uuidString, alertType: type, severity: severity,
            title: title, message: message, sourceId: sourceId, sourceType: sourceType,
            recordedAt: Date().timeIntervalSince1970, acknowledged: false
        )
        do {
            try db.write { database in
                try database.execute(sql: """
                    INSERT INTO monitoring_alerts (id, alertType, severity, title, message, sourceId, sourceType, recordedAt, acknowledged)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [alert.id, alert.alertType, alert.severity, alert.title, alert.message, alert.sourceId, alert.sourceType, alert.recordedAt, 0])
            }
            pruneAlerts()
            log.warning("ALERT [\(severity)] \(title): \(message)")
        } catch {
            log.warning("Failed to store alert: \(error.localizedDescription)")
        }
    }

    // MARK: - Query APIs

    func recentMetrics(limit: Int = 100) -> [MetricRecord] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM monitoring_metrics ORDER BY recordedAt DESC LIMIT ?", arguments: [limit]).map { row in
                MetricRecord(id: row["id"], bucket: row["bucket"], metricName: row["metricName"], metricValue: row["metricValue"], recordedAt: row["recordedAt"])
            }
        }) ?? []
    }

    func metrics(name: String, since: Date) -> [MetricRecord] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM monitoring_metrics WHERE metricName = ? AND recordedAt >= ? ORDER BY recordedAt ASC", arguments: [name, since.timeIntervalSince1970]).map { row in
                MetricRecord(id: row["id"], bucket: row["bucket"], metricName: row["metricName"], metricValue: row["metricValue"], recordedAt: row["recordedAt"])
            }
        }) ?? []
    }

    func summary() -> MonitoringSummary {
        let totalTools = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM execution_log") }) ?? 0
        let totalWorkflows = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM workflow_executions") }) ?? 0
        let recentAlerts = (try? db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM monitoring_alerts WHERE recordedAt >= ?", arguments: [Date().addingTimeInterval(-86400).timeIntervalSince1970]) }) ?? 0
        let activeCount: Int = {
            lock.lock()
            let count = activeExecutions.count
            lock.unlock()
            return count
        }()
        let lastFailure: AlertRecord? = try? db.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM monitoring_alerts WHERE severity = 'error' ORDER BY recordedAt DESC LIMIT 1") else { return nil }
            return AlertRecord(id: row["id"], alertType: row["alertType"], severity: row["severity"], title: row["title"], message: row["message"], sourceId: row["sourceId"], sourceType: row["sourceType"], recordedAt: row["recordedAt"], acknowledged: (row["acknowledged"] as? Int) == 1)
        }
        return MonitoringSummary(totalToolExecutions: totalTools, totalWorkflowRuns: totalWorkflows, activeExecutions: activeCount, recentAlerts24h: recentAlerts, lastFailure: lastFailure)
    }

    func pendingAlerts() -> [AlertRecord] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM monitoring_alerts WHERE acknowledged = 0 ORDER BY recordedAt DESC").map { row in
                AlertRecord(id: row["id"], alertType: row["alertType"], severity: row["severity"], title: row["title"], message: row["message"], sourceId: row["sourceId"], sourceType: row["sourceType"], recordedAt: row["recordedAt"], acknowledged: (row["acknowledged"] as? Int) == 1)
            }
        }) ?? []
    }

    func acknowledgeAlert(id: String) {
        try? db.write { db in
            try db.execute(sql: "UPDATE monitoring_alerts SET acknowledged = 1 WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Execution History (reads from execution_log)

    func executionHistory(sessionId: String) -> [ExecutionLogEntry] {
        (try? db.read { db in
            try ExecutionLogEntry.fetchAll(db, sql: "SELECT * FROM execution_log WHERE sessionId = ? ORDER BY createdAt ASC", arguments: [sessionId])
        }) ?? []
    }

    func executionHistory(limit: Int = 50, offset: Int = 0) -> [ExecutionLogEntry] {
        (try? db.read { db in
            try ExecutionLogEntry.fetchAll(db, sql: "SELECT * FROM execution_log ORDER BY createdAt DESC LIMIT ? OFFSET ?", arguments: [limit, offset])
        }) ?? []
    }

    func workflowRuns(workflowId: String) -> [WorkflowExecution] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM workflow_executions WHERE workflowId = ? ORDER BY startedAt DESC", arguments: [workflowId]).map(WorkflowExecution.init(row:))
        }) ?? []
    }

    // MARK: - Replay

    func replaySteps(sessionId: String) -> [ReplayStep] {
        let entries = executionHistory(sessionId: sessionId)
        return entries.enumerated().map { i, entry in
            ReplayStep(stepIndex: i, toolName: entry.toolName, input: entry.inputJSON, output: entry.outputJSON, outcome: entry.outcome, error: entry.errorDetail, durationMs: entry.durationMs, timestamp: entry.createdAt)
        }
    }

    // MARK: - Tool Usage Stats

    func toolStats() -> [(toolName: String, count: Int, successRate: Float)] {
        (try? db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT toolName, COUNT(*) AS cnt,
                       CAST(SUM(CASE WHEN outcome = 'succeeded' OR outcome = 'success' THEN 1 ELSE 0 END) AS REAL) / CAST(COUNT(*) AS REAL) AS successRate
                FROM execution_log GROUP BY toolName ORDER BY cnt DESC
            """).map { row in
                (toolName: row["toolName"] as? String ?? "", count: Int(row["cnt"] as? Int64 ?? 0), successRate: Float(row["successRate"] as? Double ?? 0))
            }
        }) ?? []
    }

    func activeExecutionCount() -> Int {
        lock.lock()
        let count = activeExecutions.count
        lock.unlock()
        return count
    }

    // MARK: - Helpers

    private func currentBucket() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HH"
        return f.string(from: Date())
    }
}

// MARK: - Supporting Types

struct MonitoringSummary: Sendable {
    let totalToolExecutions: Int
    let totalWorkflowRuns: Int
    let activeExecutions: Int
    let recentAlerts24h: Int
    let lastFailure: AlertRecord?
}

struct ReplayStep: Sendable {
    let stepIndex: Int
    let toolName: String
    let input: String?
    let output: String?
    let outcome: String
    let error: String?
    let durationMs: Double
    let timestamp: Date
}
