import Foundation

// MARK: - Status Tool

final class MonitorStatusTool: Tool {
    var definition = ToolDefinition(
        id: "monitorStatus",
        name: "Monitor Status",
        description: "Get current monitoring summary — total executions, active operations, recent alerts.",
        inputSchema: ToolSchema(parameters: [])
    )

    private let monitoringService: MonitoringService

    init(monitoringService: MonitoringService) { self.monitoringService = monitoringService }

    func run(input: [String: String]) async throws -> String {
        let summary = monitoringService.summary()
        var s = """
        Orbit Monitoring Status
        -----------------------
        Tool Executions: \(summary.totalToolExecutions)
        Workflow Runs: \(summary.totalWorkflowRuns)
        Active Executions: \(summary.activeExecutions)
        Alerts (24h): \(summary.recentAlerts24h)
        """
        if let failure = summary.lastFailure {
            s += "\n\nLast Failure:\n  \(failure.title)\n  \(failure.message)"
        }
        return s
    }
}

// MARK: - History Tool

final class MonitorHistoryTool: Tool {
    var definition = ToolDefinition(
        id: "monitorHistory",
        name: "Monitor History",
        description: "Query execution history — recent tool calls, workflow runs, or a specific session.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "sessionId", description: "Filter by session/execution ID (optional)", type: .string, required: false),
            ToolParameter(name: "workflowId", description: "Filter by workflow definition ID (optional)", type: .string, required: false),
            ToolParameter(name: "limit", description: "Max results (default 20)", type: .integer, required: false)
        ])
    )

    private let monitoringService: MonitoringService

    init(monitoringService: MonitoringService) { self.monitoringService = monitoringService }

    func run(input: [String: String]) async throws -> String {
        let limit = input["limit"].flatMap(Int.init) ?? 20

        if let sessionId = input["sessionId"] {
            let entries = monitoringService.executionHistory(sessionId: sessionId)
            if entries.isEmpty { return "No history found for session '\(sessionId)'." }
            var s = "Session \(sessionId.prefix(12))... (\(entries.count) steps):\n"
            for entry in entries {
                let outcome = entry.outcome == "succeeded" ? "✅" : entry.outcome == "failed" ? "❌" : "⏸️"
                s += "\(outcome) [\(String(format: "%.0f", entry.durationMs))ms] \(entry.toolName)\n"
            }
            return s
        }

        if let workflowId = input["workflowId"] {
            let runs = monitoringService.workflowRuns(workflowId: workflowId)
            if runs.isEmpty { return "No runs for workflow '\(workflowId)'." }
            var s = "Runs for workflow \(workflowId.prefix(12))...:\n"
            for run in runs.prefix(limit) {
                s += "[\(run.status.rawValue)] \(run.startedAt) — \(run.completedAt.map { "\($0)" } ?? "running")\n"
            }
            return s
        }

        let entries = monitoringService.executionHistory(limit: limit)
        if entries.isEmpty { return "No execution history." }
        var s = "Recent executions (last \(limit)):\n"
        for entry in entries {
            let icon = entry.outcome == "succeeded" ? "✅" : entry.outcome == "failed" ? "❌" : "⏸️"
            s += "\(icon) \(entry.toolName) [\(String(format: "%.0f", entry.durationMs))ms] \(entry.createdAt)\n"
        }
        return s
    }
}

// MARK: - Replay Tool

final class MonitorReplayTool: Tool {
    var definition = ToolDefinition(
        id: "monitorReplay",
        name: "Monitor Replay",
        description: "Replay an execution step-by-step from stored events by session ID.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "sessionId", description: "Session/execution ID to replay", type: .string, required: true),
            ToolParameter(name: "stepIndex", description: "Show a specific step (0-based, optional — shows all if omitted)", type: .integer, required: false)
        ])
    )

    private let monitoringService: MonitoringService

    init(monitoringService: MonitoringService) { self.monitoringService = monitoringService }

    func run(input: [String: String]) async throws -> String {
        guard let sessionId = input["sessionId"], !sessionId.isEmpty else {
            return "No session ID specified."
        }

        let steps = monitoringService.replaySteps(sessionId: sessionId)
        if steps.isEmpty { return "No replay data for session '\(sessionId)'." }

        if let indexStr = input["stepIndex"],
           let index = Int(indexStr) {
            guard index >= 0, index < steps.count else { return "Step index \(index) out of range (0...\(steps.count - 1))." }
            let step = steps[index]
            return formatStep(step, title: "Step \(index) of \(steps.count)")
        }

        var s = "Replay: Session \(sessionId.prefix(12))... (\(steps.count) steps)\n"
        for step in steps {
            let icon = step.outcome == "succeeded" ? "✅" : step.outcome == "failed" ? "❌" : "⏸️"
            s += "\n\(icon) Step \(step.stepIndex): \(step.toolName) [\(String(format: "%.0f", step.durationMs))ms]"
            if let e = step.error { s += "\n   Error: \(e)" }
        }
        return s + "\n\nUse stepIndex parameter to inspect a specific step."
    }

    private func formatStep(_ step: ReplayStep, title: String) -> String {
        var s = """
        \(title)
        Tool: \(step.toolName)
        Outcome: \(step.outcome)
        Duration: \(String(format: "%.0f", step.durationMs))ms
        Timestamp: \(step.timestamp)
        """
        if let i = step.input, !i.isEmpty { s += "\nInput: \(i)" }
        if let o = step.output, !o.isEmpty { s += "\nOutput: \(o.prefix(1000))" }
        if let e = step.error { s += "\nError: \(e)" }
        return s
    }
}

// MARK: - Alerts Tool

final class MonitorAlertsTool: Tool {
    var definition = ToolDefinition(
        id: "monitorAlerts",
        name: "Monitor Alerts",
        description: "List monitoring alerts — unacknowledged failures detected by Orbit.",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "acknowledge", description: "Alert ID to acknowledge (mark as seen)", type: .string, required: false)
        ])
    )

    private let monitoringService: MonitoringService

    init(monitoringService: MonitoringService) { self.monitoringService = monitoringService }

    func run(input: [String: String]) async throws -> String {
        if let ackId = input["acknowledge"] {
            monitoringService.acknowledgeAlert(id: ackId)
            return "Alert '\(ackId.prefix(12))...' acknowledged."
        }

        let alerts = monitoringService.pendingAlerts()
        if alerts.isEmpty { return "No pending alerts. All systems nominal." }

        var s = "Pending Alerts (\(alerts.count)):\n"
        for alert in alerts {
            let icon = alert.severity == "error" ? "🔴" : alert.severity == "warning" ? "🟡" : "🔵"
            s += "\n\(icon) [\(alert.alertType)] \(alert.title)"
            s += "\n   \(alert.message)"
            s += "\n   ID: \(alert.id.prefix(12))... | \(Date(timeIntervalSince1970: alert.recordedAt))"
        }
        s += "\n\nUse acknowledge=<id> to dismiss an alert."
        return s
    }
}
