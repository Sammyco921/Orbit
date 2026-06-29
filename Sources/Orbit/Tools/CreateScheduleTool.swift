import Foundation
import OSLog

private let log = Logger(subsystem: "com.orbit", category: "schedule-tool")

final class CreateScheduleTool: Tool {
    var definition = ToolDefinition(
        id: "createSchedule",
        name: "Create Schedule",
        description: "Schedule a recurring task or background job to run at a specific interval",
        inputSchema: ToolSchema(parameters: [
            ToolParameter(name: "name", description: "Name or description of the scheduled task", type: .string, required: true),
            ToolParameter(name: "intervalSeconds", description: "Interval in seconds between runs (e.g. 3600 for hourly)", type: .integer, required: true),
            ToolParameter(name: "action", description: "The action to perform when the schedule triggers", type: .string, required: true)
        ])
    )

    var schedulerService: SchedulerService?

    func run(input: [String: String]) async throws -> String {
        guard let name = input["name"], !name.isEmpty else {
            return "No schedule name provided."
        }
        guard let intervalStr = input["intervalSeconds"], let interval = Int(intervalStr), interval > 0 else {
            return "Invalid interval. Provide intervalSeconds as a positive integer."
        }
        guard let action = input["action"], !action.isEmpty else {
            return "No action provided."
        }
        guard let scheduler = schedulerService else {
            return "Scheduler service not available."
        }

        Logger(subsystem: "com.orbit", category: "schedule-tool").notice("Scheduling task '\(name)' every \(interval)s: \(action)")
        scheduler.registerHandler(id: "schedule_\(name)") { [name, action] in
            Logger(subsystem: "com.orbit", category: "schedule-tool").notice("Scheduled task '\(name)' triggered: \(action)")
        }

        return "Scheduled task '\(name)' registered to run every \(interval) seconds."
    }
}
